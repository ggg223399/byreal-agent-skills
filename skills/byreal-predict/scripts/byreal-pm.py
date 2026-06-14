#!/usr/bin/env python3
"""byreal-pm: ticket-enforced wrapper for byreal-cli polymarket writes.

Wraps `byreal-cli polymarket order place` and `... order cancel` into a
two-step ticket -> exec flow. The wrapper exists so the LLM agent cannot:

  - Retry with modified parameters after a CLI rejection (the ticket is
    destroyed on any CLI failure).
  - Claim execution success without a readback (exec bundles execute +
    status/active-orders read into one return).
  - Batch writes through shell loops (one ticket per write, one write per
    exec invocation).

Read-only commands (order active, portfolio read, funding balance, event
search/detail, category list, account deploy --dry-run) are NOT wrapped --
the skill calls byreal-cli directly for those.

State is a single JSON file at $BYREAL_PM_STATE_DIR (default
~/.cache/byreal-predict) holding at most one pending ticket. Creating a new
ticket overwrites any previous pending ticket. Tickets expire after 60s.
Exec deletes the state file before invoking the CLI so a ticket can only
ever execute once.

Output is always a single line of JSON on stdout. Errors set exit code 1.

Terminal-mode errors that must abort the flow return a minimal payload:
{ok, terminal, error, reply_instruction, assistant_message}. The model is
expected to reproduce assistant_message verbatim. Internal debug fields are
hidden unless BYREAL_PM_DEBUG=1, so the model has no auxiliary data to riff on
when narrating the failure.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path

STATE_DIR = Path(
    os.environ.get("BYREAL_PM_STATE_DIR")
    or os.path.expanduser("~/.cache/byreal-predict")
)
TICKET_FILE = STATE_DIR / "pending-ticket.json"
TICKET_TTL_SECONDS = 60
CLI_TIMEOUT_SECONDS = 45
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

DEBUG_MODE = os.environ.get("BYREAL_PM_DEBUG") == "1"

REPLY_INSTRUCTION = (
    "Reply with the assistant_message field verbatim as your entire reply. "
    "Do not add market price, liquidity, tick size, alternatives, next-step "
    "prompts, wallet/balance commentary, or any other content."
)


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(t: datetime) -> str:
    return t.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def emit(payload: dict, exit_code: int = 0) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.exit(exit_code)


def emit_error(code: str, detail: str = "", **extra) -> None:
    payload = {"ok": False, "error": code, "detail": detail}
    payload.update(extra)
    emit(payload, exit_code=1)


def emit_terminal(error: str, assistant_message: str, **debug_extra) -> None:
    """Emit a terminal-mode error.

    The payload is intentionally minimal so the model has only assistant_message
    to consume. Debug fields are gated behind BYREAL_PM_DEBUG=1 — they exist
    for local diagnosis, not for the model to narrate from.
    """
    payload = {
        "ok": False,
        "terminal": True,
        "error": error,
        "reply_instruction": REPLY_INSTRUCTION,
        "assistant_message": assistant_message,
    }
    if DEBUG_MODE and debug_extra:
        payload["debug"] = debug_extra
    emit(payload, exit_code=1)


def safe_cli_message(payload: dict, fallback: str) -> str:
    """Extract the safest user-facing message from a CLI error payload."""
    if not isinstance(payload, dict):
        return fallback
    err = payload.get("error")
    if isinstance(err, dict):
        details = err.get("details")
        if isinstance(details, dict) and details.get("safe_user_message"):
            return str(details["safe_user_message"])
        if err.get("message"):
            return str(err["message"])
        if err.get("code"):
            return str(err["code"])
    if isinstance(err, str) and err:
        return err
    if payload.get("detail"):
        return str(payload["detail"])
    return fallback


def emit_cli_rejected_terminal(error: str, payload: dict, fallback: str) -> None:
    message = (
        "Cannot place this order yet\n\n"
        f"{safe_cli_message(payload, fallback)}"
    )
    emit_terminal(error, message, cli_output=payload)


def cli_error_payload(code: str, detail: str = "", **extra) -> dict:
    payload = {"success": False, "error": code, "detail": detail}
    payload.update(extra)
    return payload


def _extract_first_json(text: str) -> dict | None:
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


def _clean_detail(text: str) -> str:
    """Strip ANSI and ASCII-art banner so error detail stays readable."""
    text = ANSI_RE.sub("", text)
    if "╔" in text or "║" in text:
        meaningful = []
        for line in text.splitlines():
            s = line.strip()
            if not s:
                continue
            if any(c in s for c in "║╔╗╚╝═"):
                continue
            if s.startswith("⚠"):
                continue
            meaningful.append(s)
        joined = " | ".join(meaningful)[:400]
        return joined or "CLI printed help banner instead of JSON (subcommand missing in installed version?)"
    return text.strip()[:500]


def run_cli(args: list[str], *, fatal: bool = True) -> dict:
    """Invoke byreal-cli, strip banner, parse the first JSON object found."""
    try:
        result = subprocess.run(
            args, capture_output=True, text=True, timeout=CLI_TIMEOUT_SECONDS
        )
    except FileNotFoundError:
        if fatal:
            emit_error("CLI_MISSING", "byreal-cli not on PATH")
        return cli_error_payload("CLI_MISSING", "byreal-cli not on PATH")
    except subprocess.TimeoutExpired:
        if fatal:
            emit_error("CLI_TIMEOUT", " ".join(args))
        return cli_error_payload("CLI_TIMEOUT", " ".join(args))

    combined = (result.stdout or "") + (
        ("\n" + result.stderr) if result.stderr else ""
    )
    payload = _extract_first_json(combined)
    if payload is None:
        detail = _clean_detail(combined) or f"exit code {result.returncode}"
        if fatal:
            emit_error("CLI_NO_JSON", detail)
        return cli_error_payload("CLI_NO_JSON", detail)
    return payload


def cli_failed(payload: dict) -> bool:
    if not isinstance(payload, dict):
        return True
    if "error" in payload:
        return True
    if payload.get("success") is False:
        return True
    return False


def payload_data(payload: dict) -> dict:
    data = payload.get("data")
    return data if isinstance(data, dict) else {}


def decimal_value(value) -> Decimal | None:
    if value is None:
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def decimal_text(value: Decimal) -> str:
    return format(value, "f")


def prepare_limit_price(params: dict, dry_run_payload: dict) -> dict | None:
    """Record CLI-normalized limit prices and execute with that exact price."""
    if params.get("order_type") != "limit":
        return None

    requested = decimal_value(params.get("price"))
    if requested is None:
        emit_error("INVALID_PRICE", "limit price is not a valid decimal")

    data = payload_data(dry_run_payload)
    observed = []
    for key in ("signed_price", "limit_price", "order_price", "price"):
        if key not in data:
            continue
        actual = decimal_value(data.get(key))
        if actual is not None:
            observed.append((key, actual))

    if not observed:
        message = (
            "Cannot place this order yet\n\n"
            "The CLI did not return a signed or limit price to verify. "
            "No ticket was created and there is no pending confirmation."
        )
        emit_terminal(
            "PRICE_IDENTITY_MISSING",
            message,
            detail="CLI dry-run did not return a signed/limit price to verify.",
            requested_price=str(requested),
            returned_fields=sorted(str(k) for k in data.keys()),
        )

    executable_key, executable = observed[0]
    if executable == requested:
        return None

    requested_text = decimal_text(requested)
    executable_text = decimal_text(executable)
    params["price"] = executable_text
    return {
        "type": "limit_price_normalized",
        "requested_price": requested_text,
        "executable_price": executable_text,
        "source_field": executable_key,
        "observed_fields": [
            {"field": key, "value": decimal_text(actual)}
            for key, actual in observed
        ],
        "requires_user_confirmation": True,
    }


def agent_order_preview(params: dict, dry_run_payload: dict) -> dict:
    """Shape dry-run data for chat rendering without misleading limit fills."""
    data = dict(payload_data(dry_run_payload))
    if params.get("order_type") == "limit":
        data.pop("fully_fills", None)
        data["fill_policy"] = "may stay open until matched or canceled"
    return data


def order_row_id(row: dict) -> str:
    return str(row.get("order_id") or row.get("id") or "")


def active_order_rows(payload: dict) -> list[dict]:
    data = payload_data(payload)
    for key in ("orders", "active_orders"):
        orders = data.get(key)
        if isinstance(orders, list):
            return orders
    return []


def cancel_target_rows(payload: dict) -> list[dict]:
    data = payload_data(payload)
    for key in ("targets", "orders", "active_orders", "matched_orders", "candidates"):
        targets = data.get(key)
        if isinstance(targets, list):
            return targets
    if order_row_id(data):
        return [data]
    return []


def cancel_target_ids(payload: dict) -> list[str]:
    targets = cancel_target_rows(payload)
    return [oid for oid in (order_row_id(t) for t in targets) if oid]


def write_ticket(data: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = TICKET_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, TICKET_FILE)


def clear_ticket() -> None:
    TICKET_FILE.unlink(missing_ok=True)


def read_and_consume_ticket(ticket_id: str, expected_kind: str) -> dict:
    if not TICKET_FILE.exists():
        emit_error("TICKET_NOT_FOUND", "no pending ticket on file")
    try:
        data = json.loads(TICKET_FILE.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        TICKET_FILE.unlink(missing_ok=True)
        emit_error("TICKET_CORRUPT", str(exc))

    if data.get("ticket_id") != ticket_id:
        emit_error(
            "TICKET_NOT_FOUND",
            "pending ticket id does not match the provided ticket",
        )
    if data.get("kind") != expected_kind:
        emit_error(
            "TICKET_KIND_MISMATCH",
            f"pending ticket kind={data.get('kind')}, expected {expected_kind}",
        )
    expires_at = datetime.fromisoformat(
        data["expires_at"].replace("Z", "+00:00")
    )
    if now() >= expires_at:
        TICKET_FILE.unlink(missing_ok=True)
        emit_error("TICKET_EXPIRED", "create a new ticket and re-confirm")

    TICKET_FILE.unlink(missing_ok=True)
    return data


def new_ticket_id() -> str:
    return secrets.token_hex(8)


# ---------------- order ----------------


def _order_preview_cli(p: dict) -> list[str]:
    cli = [
        "byreal-cli", "polymarket", "order", "preview",
        "--token-id", p["token_id"],
        "--side", p["side"],
        "--order-type", p["order_type"],
        "-o", "json",
    ]
    if p.get("condition_id"):
        cli += ["--condition-id", p["condition_id"]]
    if p["order_type"] == "limit":
        cli += ["--price", str(p["price"]), "--size", str(p["size"])]
    elif p["side"] == "buy":
        cli += ["--amount", str(p["amount"])]
    else:
        cli += ["--size", str(p["size"])]
    if p.get("slippage_bps") is not None:
        cli += ["--slippage-bps", str(p["slippage_bps"])]
    return cli


def _order_place_cli(
    p: dict, mode_flag: str, preview_snapshot: dict | None = None
) -> list[str]:
    cli = [
        "byreal-cli", "polymarket", "order", "place",
        "--token-id", p["token_id"],
        "--side", p["side"],
        "--order-type", p["order_type"],
        mode_flag,
        "-o", "json",
    ]
    if p.get("condition_id"):
        cli += ["--condition-id", p["condition_id"]]
    if p["order_type"] == "limit":
        cli += [
            "--price", str(p["price"]),
            "--size", str(p["size"]),
        ]
    elif p["side"] == "buy":
        cli += ["--amount", str(p["amount"])]
    else:
        cli += ["--size", str(p["size"])]
    if p.get("slippage_bps") is not None:
        cli += ["--slippage-bps", str(p["slippage_bps"])]
    if p["order_type"] == "market" and preview_snapshot is not None:
        cli += [
            "--preview",
            json.dumps(preview_snapshot, separators=(",", ":")),
        ]
    return cli


def cmd_order_ticket(args) -> None:
    clear_ticket()
    params = {
        "token_id": args.token_id,
        "condition_id": args.condition_id,
        "side": args.side,
        "order_type": args.order_type,
        "amount": args.amount,
        "size": args.size,
        "price": args.price,
        "slippage_bps": args.slippage_bps,
    }

    if args.order_type == "market":
        if args.side == "buy":
            if args.amount is None:
                emit_error("MISSING_PARAM", "market buy requires --amount")
        else:
            if args.size is None:
                emit_error("MISSING_PARAM", "market sell requires --size")
        preview_payload = run_cli(_order_preview_cli(params))
        if cli_failed(preview_payload):
            emit_cli_rejected_terminal(
                "ORDER_PREVIEW_REJECTED",
                preview_payload,
                "Order preview failed.",
            )
        preview_data = payload_data(preview_payload)
        preview_snapshot = preview_data.get("preview")
        if not isinstance(preview_snapshot, dict):
            emit_error(
                "PREVIEW_SNAPSHOT_MISSING",
                "order preview did not return a preview snapshot",
                cli_output=preview_payload,
            )
    else:  # limit
        if args.price is None or args.size is None:
            emit_error("MISSING_PARAM", "limit order requires --price and --size")
        preview_data = None
        preview_snapshot = None

    dry_run_payload = run_cli(_order_place_cli(params, "--dry-run", preview_snapshot))
    if cli_failed(dry_run_payload):
        emit_cli_rejected_terminal(
            "ORDER_DRY_RUN_REJECTED",
            dry_run_payload,
            "Order dry-run failed.",
        )
    price_adjustment = prepare_limit_price(params, dry_run_payload)
    dry_run_data = agent_order_preview(params, dry_run_payload)

    ticket = {
        "ticket_id": new_ticket_id(),
        "kind": "order",
        "params": params,
        "order_preview": preview_data,
        "dry_run": dry_run_data,
        "price_adjustment": price_adjustment,
        "preview_snapshot": preview_snapshot,
        "created_at": iso(now()),
        "expires_at": iso(now() + timedelta(seconds=TICKET_TTL_SECONDS)),
    }
    write_ticket(ticket)
    emit({
        "ok": True,
        "ticket_id": ticket["ticket_id"],
        "kind": "order",
        "expires_at": ticket["expires_at"],
        "preview": ticket["dry_run"],
        "price_adjustment": price_adjustment,
        "order_preview": preview_data,
    })


def cmd_order_exec(args) -> None:
    ticket = read_and_consume_ticket(args.ticket, "order")
    p = ticket["params"]

    payload = run_cli(
        _order_place_cli(p, "--execute", ticket.get("preview_snapshot"))
    )
    if cli_failed(payload):
        emit_error(
            "CLI_REJECTED", "order place failed",
            ticket_consumed=True, cli_output=payload,
        )

    data = payload.get("data") or {}
    order_id = data.get("order_id") or data.get("id")
    post_state = None
    post_state_error = None
    if order_id:
        status_payload = run_cli([
            "byreal-cli", "polymarket", "order", "status",
            "--order-id", order_id, "-o", "json",
        ], fatal=False)
        if cli_failed(status_payload):
            post_state_error = status_payload
        else:
            post_state = status_payload.get("data")

    emit({
        "ok": True,
        "submitted": True,
        "order_id": order_id,
        "execute_result": data,
        "post_state": post_state,
        "post_state_error": post_state_error,
    })


# ---------------- cancel ----------------


def _cancel_cli_args(
    p: dict, execute: bool, order_id: str | None = None
) -> list[str]:
    cli = [
        "byreal-cli", "polymarket", "order", "cancel",
        "--execute" if execute else "--dry-run",
        "-o", "json",
    ]
    if order_id:
        cli += ["--order-id", order_id]
        return cli
    if p.get("all"):
        cli += ["--all"]
    order_ids = p.get("order_id") or []
    if len(order_ids) == 1:
        cli += ["--order-id", order_ids[0]]
    if p.get("asset_id"):
        cli += ["--asset-id", p["asset_id"]]
    if p.get("market"):
        cli += ["--market", p["market"]]
    return cli


def _cancel_preview_payload(params: dict, *, allow_missing: bool = False) -> dict:
    order_ids = params.get("order_id") or []
    if len(order_ids) <= 1:
        return run_cli(_cancel_cli_args(params, execute=False))

    active = run_cli([
        "byreal-cli", "polymarket", "order", "active", "-o", "json",
    ])
    if cli_failed(active):
        return active

    wanted = set(order_ids)
    targets = [o for o in active_order_rows(active) if order_row_id(o) in wanted]
    found = {order_row_id(o) for o in targets}
    missing = sorted(wanted - found)
    if missing:
        if allow_missing:
            return {
                "success": True,
                "data": {
                    "mode": "dry-run",
                    "targets": targets,
                    "count": len(targets),
                    "missing_order_ids": missing,
                    "target_changed": True,
                },
            }
        return {
            "success": False,
            "error": "NO_MATCHING_OPEN_ORDERS",
            "detail": "some requested order ids are not active",
            "missing_order_ids": missing,
        }

    return {
        "success": True,
        "data": {
            "mode": "dry-run",
            "targets": targets,
            "count": len(targets),
        },
    }


def cmd_cancel_ticket(args) -> None:
    clear_ticket()
    if not (args.order_id or args.asset_id or args.market or args.all):
        emit_error(
            "MISSING_PARAM",
            "cancel ticket requires --order-id / --asset-id / --market / --all",
        )

    params = {
        "order_id": args.order_id,
        "asset_id": args.asset_id,
        "market": args.market,
        "all": args.all,
    }
    payload = _cancel_preview_payload(params)
    if cli_failed(payload):
        emit_error("CLI_REJECTED", "cancel dry-run failed", cli_output=payload)
    target_ids = cancel_target_ids(payload)
    if not target_ids:
        emit_error("NO_CANCEL_TARGETS", "cancel dry-run returned no target orders")

    ticket = {
        "ticket_id": new_ticket_id(),
        "kind": "cancel",
        "params": params,
        "target_order_ids": sorted(target_ids),
        "dry_run": payload_data(payload),
        "created_at": iso(now()),
        "expires_at": iso(now() + timedelta(seconds=TICKET_TTL_SECONDS)),
    }
    write_ticket(ticket)
    emit({
        "ok": True,
        "ticket_id": ticket["ticket_id"],
        "kind": "cancel",
        "expires_at": ticket["expires_at"],
        "target_order_ids": ticket["target_order_ids"],
        "preview": ticket["dry_run"],
    })


def cmd_cancel_exec(args) -> None:
    ticket = read_and_consume_ticket(args.ticket, "cancel")
    expected_ids = sorted(ticket.get("target_order_ids") or [])
    current_preview = _cancel_preview_payload(ticket["params"], allow_missing=True)
    if cli_failed(current_preview):
        emit_error(
            "CLI_REJECTED", "cancel re-read failed",
            ticket_consumed=True, cli_output=current_preview,
        )
    current_ids = sorted(cancel_target_ids(current_preview))
    if current_ids != expected_ids:
        emit_error(
            "CANCEL_TARGET_CHANGED",
            "current cancel targets differ from the ticket preview",
            ticket_consumed=True,
            expected_order_ids=expected_ids,
            current_order_ids=current_ids,
        )

    canceled = []
    cancel_results = []
    for oid in expected_ids:
        payload = run_cli(_cancel_cli_args({}, execute=True, order_id=oid))
        if cli_failed(payload):
            emit_error(
                "CLI_REJECTED", "cancel execute failed",
                ticket_consumed=True,
                failed_order_id=oid,
                canceled_so_far=canceled,
                cli_output=payload,
            )
        canceled.append(oid)
        cancel_results.append(payload_data(payload))

    active = run_cli([
        "byreal-cli", "polymarket", "order", "active", "-o", "json",
    ], fatal=False)
    post_state_error = active if cli_failed(active) else None
    post_state = None if post_state_error else active.get("data")

    emit({
        "ok": True,
        "submitted": True,
        "canceled_order_ids": canceled,
        "cancel_results": cancel_results,
        "post_state": post_state,
        "post_state_error": post_state_error,
    })


# ---------------- argparse ----------------


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="byreal-pm",
        description="Ticket-enforced wrapper for byreal-cli polymarket writes.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    order = sub.add_parser("order", help="order ticket / order exec")
    order_sub = order.add_subparsers(dest="action", required=True)

    ot = order_sub.add_parser("ticket", help="create order ticket (runs preview/dry-run)")
    ot.add_argument("--token-id", required=True)
    ot.add_argument("--condition-id")
    ot.add_argument("--side", required=True, choices=["buy", "sell"])
    ot.add_argument("--order-type", default="market", choices=["market", "limit"])
    ot.add_argument("--amount", help="USDC amount (market buy)")
    ot.add_argument("--size", help="shares (sell or limit)")
    ot.add_argument("--price", help="limit price")
    ot.add_argument("--slippage-bps", type=int)
    ot.set_defaults(func=cmd_order_ticket)

    oe = order_sub.add_parser("exec", help="execute an order ticket")
    oe.add_argument("--ticket", required=True)
    oe.set_defaults(func=cmd_order_exec)

    cancel = sub.add_parser("cancel", help="cancel ticket / cancel exec")
    cancel_sub = cancel.add_subparsers(dest="action", required=True)

    ct = cancel_sub.add_parser("ticket", help="create cancel ticket (runs cancel --dry-run)")
    ct.add_argument("--order-id", action="append", help="repeatable")
    ct.add_argument("--asset-id")
    ct.add_argument("--market")
    ct.add_argument("--all", action="store_true")
    ct.set_defaults(func=cmd_cancel_ticket)

    ce = cancel_sub.add_parser("exec", help="execute a cancel ticket")
    ce.add_argument("--ticket", required=True)
    ce.set_defaults(func=cmd_cancel_exec)

    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
