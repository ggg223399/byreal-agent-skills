#!/usr/bin/env python3
"""Polymarket Sports REST helper for live status and fixture reads."""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any


DEFAULT_BASE_URL = "https://gateway.polymarket.us"
DEFAULT_LEAGUE = "fwc"
HTTP_TIMEOUT_SECONDS = 20
LEAGUE_RE = re.compile(r"^[a-z0-9-]+$")
LEAGUE_LABELS = {
    "fwc": "World Cup",
    "mlb": "MLB",
}

SOURCE = "Polymarket Sports REST"
REPLY_INSTRUCTION = (
    "Reply with the assistant_message field verbatim as your entire reply. "
    "Do not add web search results, schedule inference, Polymarket prices, "
    "or extra commentary."
)


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.exit(exit_code)


def emit_terminal(error: str, assistant_message: str, **extra: Any) -> None:
    payload = {
        "ok": False,
        "terminal": True,
        "error": error,
        "reply_instruction": REPLY_INSTRUCTION,
        "assistant_message": assistant_message,
    }
    payload.update(extra)
    emit(payload, exit_code=1)


def checked_at() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def validate_league(league: str) -> str:
    if not LEAGUE_RE.fullmatch(league):
        raise ValueError(f"Invalid league slug: {league}")
    return league


def fetch_json(base_url: str, league: str) -> Any:
    league = validate_league(league)
    url = f"{base_url.rstrip('/')}/v2/leagues/{league}/events"
    request = urllib.request.Request(
        url,
        headers={
            "accept": "application/json",
            "user-agent": "byreal-predict-sports-helper/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"HTTP {exc.code} from Polymarket Sports REST") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Network error from Polymarket Sports REST: {exc.reason}") from exc
    except TimeoutError as exc:
        raise RuntimeError("Polymarket Sports REST timed out") from exc
    return json.loads(raw)


def raw_events(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        events = payload.get("events")
        if isinstance(events, list):
            return [item for item in events if isinstance(item, dict)]
    return []


def state_of(event: dict[str, Any]) -> dict[str, Any]:
    state = event.get("eventState")
    if not isinstance(state, dict):
        state = {}

    period = state.get("period") or event.get("period")
    score = state.get("score") or event.get("score")
    elapsed = state.get("elapsed") or event.get("elapsed")
    live = state.get("live") if "live" in state else event.get("live")
    ended = state.get("ended") if "ended" in state else event.get("ended")
    updated_at = state.get("updatedAt") or event.get("updatedAt")
    sportradar_game_id = state.get("sportradarGameId") or event.get("sportradarGameId")

    return {
        "period": period,
        "score": score,
        "elapsed": elapsed,
        "live": live,
        "ended": ended,
        "updated_at": updated_at,
        "sportradar_game_id": sportradar_game_id,
    }


def normalize_event(event: dict[str, Any]) -> dict[str, Any]:
    state = state_of(event)
    title = event.get("title") or event.get("name") or event.get("slug") or "Unknown match"
    start_time = event.get("startTime") or event.get("startDate")
    return {
        "id": str(event.get("id") or ""),
        "title": title,
        "slug": event.get("slug"),
        "league": event.get("league") or event.get("seriesSlug"),
        "start_time": start_time,
        **state,
    }


def normalize_events(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [normalize_event(event) for event in events]


def is_live(event: dict[str, Any]) -> bool:
    return event.get("live") is True and event.get("ended") is not True


def is_ended(event: dict[str, Any]) -> bool:
    period = str(event.get("period") or "").upper()
    return event.get("ended") is True or period in {"FT", "AET", "PEN"}


def event_matches(event: dict[str, Any], query: str) -> bool:
    haystack = " ".join(
        str(event.get(key) or "") for key in ("title", "slug", "id")
    ).lower()
    tokens = [token for token in re.split(r"[^a-z0-9]+", query.lower()) if token]
    return all(token in haystack for token in tokens)


def status_text(event: dict[str, Any], lang: str) -> str:
    if is_live(event):
        return "live" if lang == "en" else "\u8fdb\u884c\u4e2d"
    if is_ended(event):
        return "ended" if lang == "en" else "\u5df2\u7ed3\u675f"
    period = str(event.get("period") or "").upper()
    if period == "NS":
        return "not started" if lang == "en" else "\u672a\u5f00\u59cb"
    return str(event.get("period") or ("unknown" if lang == "en" else "\u672a\u77e5"))


def render_live(events: list[dict[str, Any]], lang: str, league_label: str) -> str:
    live_events = [event for event in events if is_live(event)]
    if lang == "zh":
        if not live_events:
            return "\n".join(
                [
                    f"**{league_label}**",
                    f"\u68c0\u67e5: {checked_at()}",
                    "\u8fdb\u884c\u4e2d\u6bd4\u8d5b: 0",
                    "",
                    f"\u6765\u6e90: {SOURCE}",
                ]
            )
        lines = [f"**{league_label} - \u8fdb\u884c\u4e2d**", f"\u68c0\u67e5: {checked_at()}", ""]
        for idx, event in enumerate(live_events, start=1):
            lines.extend(render_event_lines(event, idx, "zh"))
            lines.append("")
        lines.append(f"\u6765\u6e90: {SOURCE}")
        return "\n".join(lines).rstrip()

    if not live_events:
        return "\n".join(
            [
                f"**{league_label}**",
                f"Checked: {checked_at()}",
                "Matches in progress: 0",
                "",
                f"Source: {SOURCE}",
            ]
        )
    lines = [f"**{league_label} - Matches in progress**", f"Checked: {checked_at()}", ""]
    for idx, event in enumerate(live_events, start=1):
        lines.extend(render_event_lines(event, idx, "en"))
        lines.append("")
    lines.append(f"Source: {SOURCE}")
    return "\n".join(lines).rstrip()


def render_event_lines(event: dict[str, Any], idx: int | None, lang: str) -> list[str]:
    prefix = f"{idx}. " if idx is not None else ""
    lines = [f"{prefix}**{event['title']}**"]
    status = status_text(event, lang)
    if lang == "zh":
        lines.append(f"\u72b6\u6001: {status}")
        if event.get("score"):
            lines.append(f"\u6bd4\u5206: {event['score']}")
        period = str(event.get("period") or "").upper()
        if event.get("elapsed") or (event.get("period") and period != "NS"):
            value = event.get("elapsed") or event.get("period")
            lines.append(f"\u65f6\u95f4: {value}")
        if event.get("start_time"):
            lines.append(f"\u5f00\u7403: {event['start_time']}")
        return lines

    lines.append(f"Status: {status}")
    if event.get("score"):
        lines.append(f"Score: {event['score']}")
    period = str(event.get("period") or "").upper()
    if event.get("elapsed") or (event.get("period") and period != "NS"):
        value = event.get("elapsed") or event.get("period")
        lines.append(f"Minute: {value}")
    if event.get("start_time"):
        lines.append(f"Kickoff: {event['start_time']}")
    return lines


def render_status(matches: list[dict[str, Any]], lang: str, query: str) -> str:
    if not matches:
        if lang == "zh":
            return "\n".join(
                [
                    "\u672a\u627e\u5230\u8fd9\u573a\u6bd4\u8d5b\u7684\u5b9e\u65f6\u72b6\u6001\u3002",
                    "",
                    f"\u67e5\u8be2: {query}",
                    f"\u6765\u6e90: {SOURCE}",
                ]
            )
        return "\n".join(
            [
                "I could not find live status for that match.",
                "",
                f"Query: {query}",
                f"Source: {SOURCE}",
            ]
        )

    event = matches[0]
    lines = render_event_lines(event, None, lang)
    if lang == "zh":
        lines.extend([f"\u68c0\u67e5: {checked_at()}", f"\u6765\u6e90: {SOURCE}"])
    else:
        lines.extend([f"Checked: {checked_at()}", f"Source: {SOURCE}"])
    return "\n".join(lines)


def fixtures_payload(events: list[dict[str, Any]]) -> list[dict[str, str]]:
    rows = []
    for event in events:
        if not event.get("start_time"):
            continue
        rows.append({"match": event["title"], "kickoff": event["start_time"]})
    return rows


def load_events(args) -> list[dict[str, Any]]:
    payload = fetch_json(args.base_url, args.league)
    events = normalize_events(raw_events(payload))
    if not events:
        raise RuntimeError("Polymarket Sports REST returned no events")
    return events


def cmd_live(args) -> dict[str, Any]:
    events = load_events(args)
    league_label = args.league_label or LEAGUE_LABELS.get(args.league, args.league.upper())
    message = render_live(events, args.language, league_label)
    return {
        "ok": True,
        "terminal": True,
        "assistant_message": message,
        "reply_instruction": REPLY_INSTRUCTION,
        "source": SOURCE,
        "league": args.league,
        "checked_at": checked_at(),
        "live_count": sum(1 for event in events if is_live(event)),
        "events": [event for event in events if is_live(event)],
    }


def cmd_status(args) -> dict[str, Any]:
    events = load_events(args)
    matches = [event for event in events if event_matches(event, args.query)]
    message = render_status(matches, args.language, args.query)
    return {
        "ok": True,
        "terminal": True,
        "assistant_message": message,
        "reply_instruction": REPLY_INSTRUCTION,
        "source": SOURCE,
        "league": args.league,
        "checked_at": checked_at(),
        "matches": matches[:5],
    }


def cmd_fixtures(args) -> dict[str, Any]:
    events = load_events(args)
    return {
        "ok": True,
        "source": SOURCE,
        "league": args.league,
        "fixtures": fixtures_payload(events),
    }


def main(argv=None) -> int:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--base-url", default=DEFAULT_BASE_URL)
    common.add_argument("--league", default=DEFAULT_LEAGUE)
    common.add_argument("--league-label")
    common.add_argument("--language", choices=["en", "zh"], default="en")
    parser = argparse.ArgumentParser(parents=[common])
    subparsers = parser.add_subparsers(dest="command", required=True)

    live = subparsers.add_parser("live", parents=[common])
    live.set_defaults(func=cmd_live)

    status = subparsers.add_parser("status", parents=[common])
    status.add_argument("--query", required=True)
    status.set_defaults(func=cmd_status)

    fixtures = subparsers.add_parser("fixtures", parents=[common])
    fixtures.set_defaults(func=cmd_fixtures)

    args = parser.parse_args(argv)
    try:
        payload = args.func(args)
    except Exception as exc:  # noqa: BLE001 - helper must return JSON errors.
        message = "I cannot confirm live match status from Polymarket Sports REST right now."
        if getattr(args, "language", "en") == "zh":
            message = (
                "\u6211\u73b0\u5728\u65e0\u6cd5\u4ece Polymarket Sports REST "
                "\u786e\u8ba4\u6bd4\u8d5b\u5b9e\u65f6\u72b6\u6001\u3002"
            )
        emit_terminal(
            "POLYMARKET_SPORTS_UNAVAILABLE",
            message,
            detail=str(exc),
        )
    emit(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
