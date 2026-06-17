#!/usr/bin/env bash
# Format deterministic post-cycle accounting for one completed round trip.
# The caller must pass actual executed amounts and the setup price snapshot.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

python3 - "$@" <<'PY'
import argparse
import json
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP


def dec(raw: str, name: str, *, positive: bool = False, nonnegative: bool = False) -> Decimal:
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, ValueError):
        raise ValueError(f"{name} must be numeric")
    if not value.is_finite():
        raise ValueError(f"{name} must be finite")
    if positive and value <= 0:
        raise ValueError(f"{name} must be > 0")
    if nonnegative and value < 0:
        raise ValueError(f"{name} must be >= 0")
    return value


def bool_or_none(raw: str):
    value = (raw or "").strip().lower()
    if value in ("true", "yes", "1", "confirmed", "finalized"):
        return True
    if value in ("false", "no", "0", "unconfirmed"):
        return False
    if value in ("unknown", "null", "none", ""):
        return None
    raise ValueError(f"invalid confirmation value: {raw}")


def dec_num(value: Decimal):
    return float(value)


def dec_plain(value: Decimal) -> str:
    out = format(value.normalize(), "f")
    if "." in out:
        out = out.rstrip("0").rstrip(".")
    return out or "0"


def q(value: Decimal, places: str) -> Decimal:
    return value.quantize(Decimal(places), rounding=ROUND_HALF_UP)


def usd_text(value: Decimal) -> str:
    sign = "-" if value < 0 else ""
    abs_value = -value if value < 0 else value
    if abs_value >= Decimal("1"):
        body = format(q(abs_value, "0.01"), "f")
    elif abs_value >= Decimal("0.0001"):
        body = format(q(abs_value, "0.0001"), "f")
    else:
        body = format(q(abs_value, "0.000001"), "f")
    return f"{sign}${body}"


def pct_text(value: Decimal) -> str:
    return f"{format(q(value, '0.01'), 'f')}%"


def tx_url(sig: str) -> str:
    return f"https://solscan.io/tx/{sig}"


class Parser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"usage_error:{message}", file=sys.stderr)
        sys.exit(1)


parser = Parser(
    prog="format-cycle-report.sh",
    description="Format Byreal trading competition round-trip accounting."
)
parser.add_argument("--pool", required=True)
parser.add_argument("--start-symbol", required=True)
parser.add_argument("--other-symbol", required=True)
parser.add_argument("--start-mint", required=True)
parser.add_argument("--other-mint", required=True)
parser.add_argument("--start-usd-price", required=True)
parser.add_argument("--other-usd-price", required=True)
parser.add_argument("--first-in", required=True)
parser.add_argument("--first-out", required=True)
parser.add_argument("--first-pi-pct", required=True)
parser.add_argument("--first-tx", required=True)
parser.add_argument("--first-confirmed", default="unknown")
parser.add_argument("--return-in", required=True)
parser.add_argument("--return-out", required=True)
parser.add_argument("--return-pi-pct", required=True)
parser.add_argument("--return-tx", required=True)
parser.add_argument("--return-confirmed", default="unknown")
parser.add_argument("--start-balance-after")
parser.add_argument("--other-balance-after")
parser.add_argument("--token-account-rent-usd")
parser.add_argument("--rank-credit-multiplier", default="1")

try:
    args = parser.parse_args()

    start_price = dec(args.start_usd_price, "start_usd_price", positive=True)
    other_price = dec(args.other_usd_price, "other_usd_price", positive=True)
    first_in = dec(args.first_in, "first_in", positive=True)
    first_out = dec(args.first_out, "first_out", nonnegative=True)
    first_pi = dec(args.first_pi_pct, "first_pi_pct")
    return_in = dec(args.return_in, "return_in", nonnegative=True)
    return_out = dec(args.return_out, "return_out", nonnegative=True)
    return_pi = dec(args.return_pi_pct, "return_pi_pct")
    multiplier = dec(args.rank_credit_multiplier, "rank_credit_multiplier", positive=True)
    first_confirmed = bool_or_none(args.first_confirmed)
    return_confirmed = bool_or_none(args.return_confirmed)
    start_balance_after = (
        dec(args.start_balance_after, "start_balance_after", nonnegative=True)
        if args.start_balance_after is not None
        else None
    )
    other_balance_after = (
        dec(args.other_balance_after, "other_balance_after", nonnegative=True)
        if args.other_balance_after is not None
        else None
    )
    rent_usd = (
        dec(args.token_account_rent_usd, "token_account_rent_usd", nonnegative=True)
        if args.token_account_rent_usd is not None
        else None
    )
except SystemExit:
    raise
except Exception as exc:
    print(f"parse_error:{exc}", file=sys.stderr)
    sys.exit(5)

first_swap_usd = first_in * start_price
return_swap_usd = return_in * other_price
cycle_volume_usd = first_swap_usd + return_swap_usd
projected_rank_credit_usd = cycle_volume_usd * multiplier

cost_start_units = first_in - return_out
cost_usd = cost_start_units * start_price
cost_pct = (cost_start_units / first_in) * Decimal("100")

warnings = []
if first_confirmed is not True or return_confirmed is not True:
    warnings.append("confirmation status is not fully confirmed; poll signatures or balances before reconciliation")
if first_out != return_in:
    tolerance = max(abs(first_out) * Decimal("0.000001"), Decimal("0.000000001"))
    if abs(first_out - return_in) > tolerance:
        warnings.append("return swap input differs from first swap output; accounting uses the executed return input for volume")
if cost_usd < 0:
    warnings.append("round trip ended with a local gain before any token-account rent")

balances = {}
if start_balance_after is not None:
    balances["start_after"] = {
        "amount": dec_num(start_balance_after),
        "amount_text": f"{dec_plain(start_balance_after)} {args.start_symbol}",
        "symbol": args.start_symbol,
        "mint": args.start_mint,
    }
if other_balance_after is not None:
    balances["other_after"] = {
        "amount": dec_num(other_balance_after),
        "amount_text": f"{dec_plain(other_balance_after)} {args.other_symbol}",
        "symbol": args.other_symbol,
        "mint": args.other_mint,
    }

local_accounting = {
    "first_swap_usd": dec_num(first_swap_usd),
    "first_swap_usd_text": usd_text(first_swap_usd),
    "return_swap_usd": dec_num(return_swap_usd),
    "return_swap_usd_text": usd_text(return_swap_usd),
    "cycle_volume_usd": dec_num(cycle_volume_usd),
    "cycle_volume_usd_text": usd_text(cycle_volume_usd),
    "cost_start_units": dec_num(cost_start_units),
    "cost_start_units_text": f"{dec_plain(cost_start_units)} {args.start_symbol}",
    "cost_usd": dec_num(cost_usd),
    "cost_usd_text": usd_text(cost_usd),
    "cost_pct": dec_num(cost_pct),
    "cost_pct_text": pct_text(cost_pct),
    "projected_rank_credit_usd": dec_num(projected_rank_credit_usd),
    "projected_rank_credit_usd_text": usd_text(projected_rank_credit_usd),
    "rank_credit_multiplier": dec_num(multiplier),
}
if rent_usd is not None:
    local_accounting["token_account_rent_usd"] = dec_num(rent_usd)
    local_accounting["token_account_rent_usd_text"] = usd_text(rent_usd)

out = {
    "pool_name": args.pool,
    "labels": {
        "first_swap": "first swap",
        "return_swap": "return swap",
        "volume": "volume",
        "credited_volume": "credited trading volume",
    },
    "first_swap": {
        "label": "first swap",
        "direction": f"{args.start_symbol} -> {args.other_symbol}",
        "input_amount": dec_num(first_in),
        "input_text": f"{dec_plain(first_in)} {args.start_symbol}",
        "input_mint": args.start_mint,
        "output_amount": dec_num(first_out),
        "output_text": f"{dec_plain(first_out)} {args.other_symbol}",
        "output_mint": args.other_mint,
        "priceImpactPct": dec_num(first_pi),
        "priceImpactPct_text": pct_text(first_pi),
        "tx": args.first_tx,
        "tx_url": tx_url(args.first_tx),
        "confirmed": first_confirmed,
    },
    "return_swap": {
        "label": "return swap",
        "direction": f"{args.other_symbol} -> {args.start_symbol}",
        "input_amount": dec_num(return_in),
        "input_text": f"{dec_plain(return_in)} {args.other_symbol}",
        "input_mint": args.other_mint,
        "output_amount": dec_num(return_out),
        "output_text": f"{dec_plain(return_out)} {args.start_symbol}",
        "output_mint": args.start_mint,
        "priceImpactPct": dec_num(return_pi),
        "priceImpactPct_text": pct_text(return_pi),
        "tx": args.return_tx,
        "tx_url": tx_url(args.return_tx),
        "confirmed": return_confirmed,
    },
    "local_accounting": local_accounting,
    "balances": balances,
    "render_order": [
        "first_swap.tx_url",
        "return_swap.tx_url",
        "first_swap.input_text",
        "first_swap.output_text",
        "return_swap.input_text",
        "return_swap.output_text",
        "local_accounting.cycle_volume_usd_text",
        "local_accounting.cost_start_units_text",
        "local_accounting.cost_usd_text",
        "balances",
    ],
    "warnings": warnings,
}

json.dump(out, sys.stdout, indent=2, sort_keys=True)
print()
PY
