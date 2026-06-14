#!/usr/bin/env python3
"""CLI-backed account readers for Byreal Polymarket."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation

CLI_TIMEOUT_SECONDS = 45
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

REPLY_INSTRUCTION = (
    "Reply with the assistant_message field verbatim as your entire reply. "
    "Do not add Console links, support advice, screenshots, inferred balances, "
    "computed PnL, or next-step prompts."
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
        return {"success": False, "error": {"code": "CLI_MISSING", "message": "byreal-cli not on PATH"}}
    except subprocess.TimeoutExpired:
        return {"success": False, "error": {"code": "CLI_TIMEOUT", "message": " ".join(args)}}

    combined = (result.stdout or "") + (("\n" + result.stderr) if result.stderr else "")
    payload = extract_first_json(combined)
    if payload is None:
        return {
            "success": False,
            "error": {"code": "CLI_NO_JSON", "message": combined.strip()[:500]},
        }
    return payload


def cli_failed(payload: dict) -> bool:
    return not isinstance(payload, dict) or payload.get("success") is False or "error" in payload


def payload_data(payload: dict) -> dict:
    data = payload.get("data")
    return data if isinstance(data, dict) else {}


def error_obj(payload: dict) -> dict:
    err = payload.get("error")
    return err if isinstance(err, dict) else {"message": str(err or "Unknown CLI error")}


def safe_error_text(payload: dict) -> str:
    err = error_obj(payload)
    details = err.get("details")
    if isinstance(details, dict) and details.get("safe_user_message"):
        return str(details["safe_user_message"])
    return str(err.get("message") or err.get("code") or "CLI returned an error")


def error_code(payload: dict) -> str:
    err = error_obj(payload)
    return str(err.get("code") or "CLI_ERROR")


def blocker_message(language: str, action: str, payload: dict) -> str:
    text = safe_error_text(payload)
    code = error_code(payload)
    if language.lower().startswith("zh"):
        return (
            f"\u65e0\u6cd5\u8bfb\u53d6 Polymarket {action}\u3002\n\n"
            f"CLI \u8fd4\u56de\uff1a{text}\n"
            f"\u9519\u8bef\u4ee3\u7801\uff1a`{code}`"
        )
    return (
        f"Cannot read Polymarket {action}.\n\n"
        f"CLI returned: {text}\n"
        f"Error code: `{code}`"
    )


def decimal_text(value) -> str | None:
    try:
        d = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        return None
    sign = "+" if d > 0 else ""
    return f"{sign}${d:.2f}"


def find_summary_pnl(data: dict):
    summary = data.get("summary")
    if not isinstance(summary, dict):
        return None, None
    for key in ("pnl_usd", "unrealized_pnl", "unrealized_pnl_usd", "pnl"):
        if key in summary:
            return key, summary.get(key)
    return None, None


def preflight_proxy(language: str, action: str) -> None:
    dry_run = run_cli([
        "byreal-cli", "polymarket", "account", "deploy", "--dry-run", "-o", "json",
    ])
    if cli_failed(dry_run):
        emit_terminal("ACCOUNT_PREFLIGHT_FAILED", blocker_message(language, action, dry_run))

    status = str(payload_data(dry_run).get("status") or "").upper()
    if status in ("READY", "DEPLOYED", "INITIALIZED"):
        return

    execute = run_cli([
        "byreal-cli", "polymarket", "account", "deploy", "--execute", "-o", "json",
    ])
    if cli_failed(execute):
        emit_terminal("ACCOUNT_DEPLOY_FAILED", blocker_message(language, action, execute))


def cmd_pnl(args) -> None:
    action_label = "\u6d6e\u52a8\u76c8\u4e8f" if args.language.lower().startswith("zh") else "floating PnL"
    preflight_proxy(args.language, action_label)
    portfolio = run_cli([
        "byreal-cli", "polymarket", "portfolio", "read", "-o", "json",
    ])
    if cli_failed(portfolio):
        emit_terminal("PORTFOLIO_READ_FAILED", blocker_message(args.language, action_label, portfolio))

    key, value = find_summary_pnl(payload_data(portfolio))
    formatted = decimal_text(value)
    if key is None or formatted is None:
        if args.language.lower().startswith("zh"):
            message = (
                "\u65e0\u6cd5\u8bfb\u53d6 Polymarket \u6d6e\u52a8\u76c8\u4e8f\u3002\n\n"
                "CLI \u672a\u8fd4\u56de\u8d26\u6237\u7ea7\u6d6e\u52a8\u76c8\u4e8f\u5b57\u6bb5\u3002"
            )
        else:
            message = (
                "Cannot read Polymarket floating PnL.\n\n"
                "The CLI did not return an account-level floating PnL field."
            )
        emit_terminal("PNL_FIELD_MISSING", message)

    if args.language.lower().startswith("zh"):
        message = f"Polymarket \u5f53\u524d\u6d6e\u52a8\u76c8\u4e8f\uff1a**{formatted}**"
    else:
        message = f"Current Polymarket floating PnL: **{formatted}**"
    emit_terminal("PNL_READ", message, field=key)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    pnl = sub.add_parser("pnl", help="read current floating PnL from CLI fields")
    pnl.add_argument("--language", default="en")
    pnl.set_defaults(func=cmd_pnl)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
