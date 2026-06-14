#!/usr/bin/env python3
"""Resolve a requested sports market type from current byreal-cli output.

This helper is intentionally narrow. It reads current Polymarket Event detail
through byreal-cli and returns either matching Markets or a terminal
assistant_message. It prevents the agent from turning "no matching total/spread
market" into a summary of unrelated moneyline markets.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

CLI_TIMEOUT_SECONDS = 45
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

REPLY_INSTRUCTION = (
    "Reply with the assistant_message field verbatim as your entire reply. "
    "Do not add available markets, prices, counts, related candidates, "
    "alternatives, or next-step prompts."
)


def emit(payload: dict, exit_code: int = 0) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.exit(exit_code)


def emit_terminal(error: str, assistant_message: str, **extra) -> None:
    payload = {
        "ok": False,
        "terminal": True,
        "error": error,
        "reply_instruction": REPLY_INSTRUCTION,
        "assistant_message": assistant_message,
    }
    payload.update(extra)
    emit(payload, exit_code=1)


def extract_first_json(text: str) -> dict | None:
    text = ANSI_RE.sub("", text)
    decoder = json.JSONDecoder()
    idx = text.find("{")
    while idx != -1:
        try:
            obj, _ = decoder.raw_decode(text[idx:])
            if isinstance(obj, dict):
                return obj
        except json.JSONDecodeError:
            pass
        idx = text.find("{", idx + 1)
    return None


def run_cli(args: list[str]) -> dict:
    try:
        result = subprocess.run(
            args, capture_output=True, text=True, timeout=CLI_TIMEOUT_SECONDS
        )
    except FileNotFoundError:
        emit({"ok": False, "error": "CLI_MISSING", "detail": "byreal-cli not on PATH"}, 1)
    except subprocess.TimeoutExpired:
        emit({"ok": False, "error": "CLI_TIMEOUT", "detail": " ".join(args)}, 1)

    combined = (result.stdout or "") + (("\n" + result.stderr) if result.stderr else "")
    payload = extract_first_json(combined)
    if payload is None:
        emit({"ok": False, "error": "CLI_NO_JSON", "detail": combined.strip()[:500]}, 1)
    return payload


def payload_data(payload: dict) -> dict:
    data = payload.get("data")
    return data if isinstance(data, dict) else {}


def cli_failed(payload: dict) -> bool:
    return not isinstance(payload, dict) or payload.get("success") is False or "error" in payload


def norm(text: str) -> str:
    return re.sub(r"[^a-z0-9.+-]+", " ", text.lower()).strip()


def numbers(text: str) -> set[str]:
    return set(re.findall(r"\d+(?:\.\d+)?", text))


def market_terms(query: str) -> list[str]:
    q = norm(query)
    term_groups = [
        ("total", "totals", "over", "under", "goal", "goals", "point", "points", "score", "o/u"),
        ("spread", "handicap", "line"),
        ("prop", "player", "scorer", "assist", "card", "corner"),
        ("parlay", "same game parlay", "sgp"),
    ]
    selected = []
    for group in term_groups:
        if any(term in q for term in group):
            selected.extend(group)
    if selected:
        return selected
    return [tok for tok in q.split() if len(tok) > 2]


def market_text(market: dict) -> str:
    fields = [
        market.get("title"),
        market.get("question"),
        market.get("market_type"),
        market.get("description"),
    ]
    return norm(" ".join(str(v) for v in fields if v))


def matches_market(market: dict, query: str) -> bool:
    text = market_text(market)
    terms = market_terms(query)
    if not terms:
        return False
    if not any(norm(term) in text for term in terms):
        return False

    wanted_numbers = numbers(query)
    if wanted_numbers and not any(num in text for num in wanted_numbers):
        return False
    return True


def not_found_message(language: str, event_title: str, display_market: str) -> str:
    if language.lower().startswith("zh"):
        display_market = zh_market_label(display_market)
        return (
            "\u5f53\u524d\u53ef\u89c1\u7684 Polymarket \u6570\u636e"
            f"\u6ca1\u6709\u663e\u793a **{event_title}** \u7684 "
            f"**{display_market}** \u5e02\u573a\u3002"
        )
    return (
        "The current visible Polymarket data does not show a "
        f"**{display_market}** market for **{event_title}**."
    )


def zh_market_label(display_market: str) -> str:
    text = norm(display_market)
    nums = sorted(numbers(display_market))
    n = nums[0] if nums else ""
    if any(term in text for term in ("total", "goals", "goal", "over", "under")):
        if "under" in text:
            return f"\u603b\u8fdb\u7403\u6570\u5c0f\u4e8e {n}".strip()
        if "over" in text:
            return f"\u603b\u8fdb\u7403\u6570\u5927\u4e8e {n}".strip()
        return "\u603b\u8fdb\u7403\u6570"
    if any(term in text for term in ("spread", "handicap")):
        return "\u8ba9\u5206\u76d8"
    if "prop" in text:
        return "\u7279\u6b8a\u4e8b\u4ef6"
    return display_market


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-query", required=True)
    parser.add_argument("--market-query", required=True)
    parser.add_argument("--display-market")
    parser.add_argument("--language", default="en")
    parser.add_argument("--limit", default="5")
    args = parser.parse_args()

    search = run_cli([
        "byreal-cli", "polymarket", "event", "search",
        "--query", args.event_query,
        "--limit", str(args.limit),
        "-o", "json",
    ])
    if cli_failed(search):
        emit({"ok": False, "error": "CLI_REJECTED", "phase": "event_search", "cli_output": search}, 1)

    events = payload_data(search).get("events")
    if not isinstance(events, list) or not events:
        emit_terminal(
            "NO_EVENT_MATCH",
            not_found_message(args.language, args.event_query, args.display_market or args.market_query),
        )

    event = events[0]
    event_id = str(event.get("event_id") or event.get("id") or "")
    event_title = str(event.get("title") or args.event_query)
    if not event_id:
        emit({"ok": False, "error": "EVENT_ID_MISSING", "event": event}, 1)

    detail = run_cli([
        "byreal-cli", "polymarket", "event", "detail",
        "--event-id", event_id,
        "--full",
        "-o", "json",
    ])
    if cli_failed(detail):
        emit({"ok": False, "error": "CLI_REJECTED", "phase": "event_detail", "cli_output": detail}, 1)

    markets = payload_data(detail).get("markets")
    if not isinstance(markets, list):
        markets = []
    matches = [m for m in markets if matches_market(m, args.market_query)]
    if not matches:
        emit_terminal(
            "NO_MATCHING_MARKET_IN_EVENT",
            not_found_message(args.language, event_title, args.display_market or args.market_query),
            event={"event_id": event_id, "title": event_title},
        )

    emit({
        "ok": True,
        "event": {"event_id": event_id, "title": event_title},
        "matches": matches,
        "reply_instruction": (
            "Render only the returned matching markets. Do not include non-matching "
            "moneyline/winner/draw markets from the same Event."
        ),
    })


if __name__ == "__main__":
    main()
