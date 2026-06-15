#!/usr/bin/env python3
"""Timezone helper for sports schedule windows.

This script intentionally does not fetch sports data. It only converts and
filters source-provided fixture times so agents do not do timezone arithmetic
by hand.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


UTC = timezone.utc


def parse_timezone(value: str):
    raw = value.strip()
    upper = raw.upper()
    if upper in {"UTC", "Z"}:
        return UTC, "UTC"

    match = re.fullmatch(r"(?:UTC|GMT)?([+-])(\d{1,2})(?::?(\d{2}))?", upper)
    if match:
        sign, hours_raw, minutes_raw = match.groups()
        hours = int(hours_raw)
        minutes = int(minutes_raw or "0")
        if hours > 23 or minutes > 59:
            raise ValueError(f"Invalid UTC offset: {value}")
        delta = timedelta(hours=hours, minutes=minutes)
        if sign == "-":
            delta = -delta
        label = f"UTC{sign}{hours:02d}:{minutes:02d}"
        if minutes == 0:
            label = f"UTC{sign}{hours}"
        return timezone(delta), label

    try:
        return ZoneInfo(raw), raw
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"Unknown timezone: {value}") from exc


def parse_kickoff(value: str) -> datetime:
    text = value.strip()
    normalized = re.sub(r"(?<=\d)T(?=\d)", " ", text)
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + " UTC"
    normalized = re.sub(r"\s+", " ", normalized)

    utc_match = re.fullmatch(
        r"(\d{4}-\d{2}-\d{2})[ ](\d{1,2}):(\d{2})(?::\d{2})?[ ]UTC",
        normalized,
        flags=re.IGNORECASE,
    )
    if utc_match:
        d_raw, hour_raw, minute_raw = utc_match.groups()
        return datetime.fromisoformat(
            f"{d_raw} {int(hour_raw):02d}:{minute_raw}"
        ).replace(tzinfo=UTC)

    offset_match = re.fullmatch(
        r"(\d{4}-\d{2}-\d{2})[ ](\d{1,2}):(\d{2})(?::\d{2})?[ ](UTC|GMT)?([+-]\d{1,2}(?::?\d{2})?)",
        normalized,
        flags=re.IGNORECASE,
    )
    if offset_match:
        d_raw, hour_raw, minute_raw, _prefix, offset_raw = offset_match.groups()
        tz, _label = parse_timezone(offset_raw)
        return datetime.fromisoformat(
            f"{d_raw} {int(hour_raw):02d}:{minute_raw}"
        ).replace(tzinfo=tz)

    iso_text = text.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(iso_text)
    except ValueError as exc:
        raise ValueError(f"Kickoff needs explicit timezone: {value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"Kickoff needs explicit timezone: {value}")
    return parsed


def fmt(dt: datetime, tz_label: str | None = None) -> str:
    if tz_label:
        return dt.strftime("%Y-%m-%d %H:%M ") + tz_label
    if dt.utcoffset() == timedelta(0):
        return dt.astimezone(UTC).strftime("%Y-%m-%d %H:%M UTC")
    return dt.isoformat(timespec="minutes")


def local_window(local_date: date, tz, kind: str):
    if kind == "tonight":
        start = datetime.combine(local_date, time(18, 0), tzinfo=tz)
        end = datetime.combine(local_date + timedelta(days=1), time(6, 0), tzinfo=tz)
        return start, end
    if kind == "today":
        start = datetime.combine(local_date, time(0, 0), tzinfo=tz)
        end = datetime.combine(local_date + timedelta(days=1), time(0, 0), tzinfo=tz)
        return start, end
    raise ValueError(f"Unsupported window kind: {kind}")


def window_payload(args):
    tz, tz_label = parse_timezone(args.timezone)
    local_date = date.fromisoformat(args.date)
    start, end = local_window(local_date, tz, args.kind)
    return {
        "timezone": tz_label,
        "kind": args.kind,
        "local_start": fmt(start, tz_label),
        "local_end": fmt(end, tz_label),
        "utc_start": fmt(start.astimezone(UTC)),
        "utc_end": fmt(end.astimezone(UTC)),
    }


def convert_payload(args):
    tz, tz_label = parse_timezone(args.timezone)
    kickoff = parse_kickoff(args.kickoff)
    kickoff_utc = kickoff.astimezone(UTC)
    kickoff_local = kickoff.astimezone(tz)
    return {
        "kickoff_utc": fmt(kickoff_utc),
        "your_time": fmt(kickoff_local, tz_label),
    }


def read_fixtures(args) -> list[dict[str, Any]]:
    if args.fixtures_json:
        data = json.loads(args.fixtures_json)
    else:
        data = json.load(sys.stdin)
    if not isinstance(data, list):
        raise ValueError("Fixtures must be a JSON array")
    return data


def filter_payload(args):
    base = window_payload(args)
    tz, tz_label = parse_timezone(args.timezone)
    local_start = parse_kickoff(base["local_start"])
    local_end = parse_kickoff(base["local_end"])
    rows = []
    errors = []

    for item in read_fixtures(args):
        title = item.get("match") or item.get("title") or item.get("name")
        kickoff_raw = item.get("kickoff") or item.get("time")
        if not title or not kickoff_raw:
            errors.append({"fixture": item, "error": "fixture needs match/title/name and kickoff/time"})
            continue
        try:
            kickoff = parse_kickoff(str(kickoff_raw))
        except ValueError as exc:
            errors.append({"fixture": item, "error": str(exc)})
            continue
        kickoff_utc = kickoff.astimezone(UTC)
        kickoff_local = kickoff.astimezone(tz)
        if local_start <= kickoff_local < local_end:
            rows.append(
                {
                    "match": title,
                    "kickoff_utc": fmt(kickoff_utc),
                    "your_time": fmt(kickoff_local, tz_label),
                }
            )

    payload = {
        **base,
        "matches": rows,
        "count": len(rows),
        "errors": errors,
    }
    payload["assistant_message"] = render_filter_message(payload, args)
    return payload


def render_filter_message(payload: dict[str, Any], args) -> str:
    lang = (args.language or "en").lower()
    scope = args.scope or ("Schedule" if lang != "zh" else "\u8d5b\u7a0b")
    source = args.source or "source"
    if lang == "zh":
        lines = [
            f"**{scope}**",
            f"\u7a97\u53e3: {payload['local_start']} \u81f3 {payload['local_end']}",
            f"\u6bd4\u8d5b: {payload['count']}",
            "",
        ]
        for idx, item in enumerate(payload["matches"], start=1):
            lines.extend(
                [
                    f"{idx}. **{item['match']}**",
                    f"\u5f00\u7403: {item['kickoff_utc']}",
                    f"\u4f60\u7684\u65f6\u95f4: {item['your_time']}",
                    "",
                ]
            )
        lines.append(f"\u6765\u6e90: {source}")
        return "\n".join(lines).rstrip()

    lines = [
        f"**{scope}**",
        f"Window: {payload['local_start']} to {payload['local_end']}",
        f"Matches: {payload['count']}",
        "",
    ]
    for idx, item in enumerate(payload["matches"], start=1):
        lines.extend(
            [
                f"{idx}. **{item['match']}**",
                f"Kickoff: {item['kickoff_utc']}",
                f"Your time: {item['your_time']}",
                "",
            ]
        )
    lines.append(f"Source: {source}")
    return "\n".join(lines).rstrip()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    window = subparsers.add_parser("window")
    window.add_argument("--timezone", required=True)
    window.add_argument("--date", required=True)
    window.add_argument("--kind", choices=["tonight", "today"], required=True)
    window.set_defaults(func=window_payload)

    convert = subparsers.add_parser("convert")
    convert.add_argument("--timezone", required=True)
    convert.add_argument("--kickoff", required=True)
    convert.set_defaults(func=convert_payload)

    filt = subparsers.add_parser("filter")
    filt.add_argument("--timezone", required=True)
    filt.add_argument("--date", required=True)
    filt.add_argument("--kind", choices=["tonight", "today"], required=True)
    filt.add_argument("--fixtures-json")
    filt.add_argument("--language", choices=["en", "zh"], default="en")
    filt.add_argument("--source")
    filt.add_argument("--scope")
    filt.set_defaults(func=filter_payload)

    args = parser.parse_args(argv)
    try:
        payload = args.func(args)
    except Exception as exc:  # noqa: BLE001 - CLI helper should return JSON errors.
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1
    print(json.dumps({"ok": True, **payload}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
