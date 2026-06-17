#!/usr/bin/env bash
# Re-quote the return swap after the first swap has actually executed.
# Owns the return-swap dry-run call so SKILL.md never has to hand-compose
# a byreal-cli call under live conditions.
#
# Used by Decision Logic step 5d (between the first swap and return swap of one cycle).
#
# Usage:
#   requote-leg.sh \
#     --input-mint <other_mint> \         # return-swap input = first-swap output mint
#     --output-mint <start_mint> \        # return-swap output = back to start mint
#     --first-swap-out-amount N \         # actual first-swap output amount
#     --first-swap-in-amount N \          # first-swap input amount
#     --wallet W \
#     [--slippage-bps 100] [--require-finite-pi]
#
# Output (stdout, JSON):
#   {
#     "input_mint":  "...",
#     "output_mint": "...",
#     "return_swap_dry_out_amount": 99.95,
#     "return_swap_priceImpactPct": 0.64,
#     "return_swap_guard_status": "price_impact_available",
#     "roundtrip_final_amount": 99.95,
#     "roundtrip_cost_pct": 0.05
#   }
#
# Stderr:  "usage: ..."             -> bad arguments
#          "return_swap_failed: <msg>" -> reverse dry-run returned success=false or non-JSON
#          "parse_error: <msg>"     -> unexpected output shape
#
# Exit codes:
#   0 = OK
#   1 = bad usage
#   3 = return-swap dry-run failed (matches dry-run-cycle.sh's return-swap exit semantics)
#   5 = parse failure
#
# Caller compares return_swap_priceImpactPct against the single-swap guard.
# With --require-finite-pi, missing/invalid priceImpactPct exits 5 so live
# runners cannot accidentally continue without guard data.

set -euo pipefail

input_mint=""
output_mint=""
first_swap_out=""
first_swap_in=""
wallet=""
slippage_bps="100"
require_finite_pi="0"

usage() {
  echo "usage: $(basename "$0") --input-mint X --output-mint Y --first-swap-out-amount N --first-swap-in-amount N --wallet W [--slippage-bps 100] [--require-finite-pi]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-mint)        input_mint="$2"; shift 2 ;;
    --output-mint)       output_mint="$2"; shift 2 ;;
    --first-swap-out-amount) first_swap_out="$2"; shift 2 ;;
    --first-swap-in-amount)  first_swap_in="$2"; shift 2 ;;
    --wallet)            wallet="$2"; shift 2 ;;
    --slippage-bps)      slippage_bps="$2"; shift 2 ;;
    --require-finite-pi) require_finite_pi="1"; shift ;;
    *) usage ;;
  esac
done

[[ -z "$input_mint" || -z "$output_mint" || -z "$first_swap_out" || -z "$first_swap_in" || -z "$wallet" ]] && usage

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v byreal-cli >/dev/null 2>&1; then
  echo "missing_command:byreal-cli" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

set +e
byreal-cli swap execute \
  --input-mint "$input_mint" --output-mint "$output_mint" \
  --amount "$first_swap_out" --slippage "$slippage_bps" \
  --wallet-address "$wallet" --dry-run -o json > "$tmp" 2>&1
exit_code=$?
set -e

if [[ $exit_code -ne 0 ]]; then
  echo "return_swap_failed: byreal-cli exited $exit_code" >&2
  cat "$tmp" >&2
  exit 3
fi

export _RESP="$tmp"
export _IN_MINT="$input_mint"
export _OUT_MINT="$output_mint"
export _FIRST_SWAP_OUT="$first_swap_out"
export _FIRST_SWAP_IN="$first_swap_in"
export _REQUIRE_FINITE_PI="$require_finite_pi"

PYTHONPATH="${script_dir}/lib${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import json, math, os, sys
from byreal_cli_json import extract_success_object_from_file

def parse_price_impact(raw):
    if raw is None or raw == "":
        return None, "missing_priceImpactPct"
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None, "invalid_priceImpactPct"
    if not math.isfinite(value):
        return None, "invalid_priceImpactPct"
    return value, "price_impact_available"

parsed = extract_success_object_from_file(os.environ["_RESP"])

if parsed is None:
    print("parse_error: return-swap dry-run output did not contain a parseable JSON object", file=sys.stderr); sys.exit(5)
if not parsed.get("success"):
    err = parsed.get("error", {}).get("message", "unknown")
    print(f"return_swap_failed: {err}", file=sys.stderr); sys.exit(3)

leg_b_out_raw = parsed.get("data", {}).get("uiOutAmount")
if leg_b_out_raw is None:
    print("parse_error: return-swap dry-run did not return uiOutAmount", file=sys.stderr); sys.exit(5)
leg_b_out = float(leg_b_out_raw)
if not math.isfinite(leg_b_out) or leg_b_out < 0:
    print("parse_error: return-swap dry-run returned invalid uiOutAmount", file=sys.stderr); sys.exit(5)
price_impact = parsed.get("data", {}).get("priceImpactPct")
price_impact, guard_status = parse_price_impact(price_impact)
if os.environ["_REQUIRE_FINITE_PI"] == "1" and guard_status != "price_impact_available":
    print(f"parse_error: return_swap_priceImpactPct {guard_status}", file=sys.stderr)
    sys.exit(5)

first_swap_out = float(os.environ["_FIRST_SWAP_OUT"])
first_swap_in  = float(os.environ["_FIRST_SWAP_IN"])

if not math.isfinite(first_swap_out) or first_swap_out <= 0:
    print("parse_error: first-swap-out-amount must be > 0", file=sys.stderr); sys.exit(5)
if not math.isfinite(first_swap_in) or first_swap_in <= 0:
    print("parse_error: first-swap-in-amount must be > 0", file=sys.stderr); sys.exit(5)

roundtrip_cost_pct = (1.0 - leg_b_out / first_swap_in) * 100.0

out = {
    "input_mint":  os.environ["_IN_MINT"],
    "output_mint": os.environ["_OUT_MINT"],
    "return_swap_dry_out_amount":   leg_b_out,
    "return_swap_priceImpactPct":   price_impact,
    "return_swap_guard_status":     guard_status,
    "roundtrip_final_amount":       leg_b_out,
    "roundtrip_cost_pct":           roundtrip_cost_pct,
}
print(json.dumps(out, indent=2))
PY
