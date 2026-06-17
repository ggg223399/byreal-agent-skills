#!/usr/bin/env bash
# Dry-run a full round-trip (start_mint -> other_mint -> start_mint) on one
# pool, computing both swaps' price impact and the combined round-trip cost.
# No execution.
#
# All swaps go through `byreal-cli swap execute` — the byreal router. Trading
# competitions only credit volume routed through byreal, so external
# aggregators (Jupiter/Titan/DFlow) are deliberately not an option here.
#
# Used by SETUP CONFIRM (one-off cost projection) and the POOL GATE step
# (per-cycle re-check before any --confirm call).
#
# Usage:
#   dry-run-cycle.sh \
#     --input-mint <start_mint> --output-mint <other_mint> \
#     --start-amount <ui_units_of_input_mint> \
#     --wallet <wallet_address> \
#     [--slippage-bps 100]
#
# Output (stdout, JSON):
#   {
#     "input_mint":  "...",
#     "output_mint": "...",
#     "start_amount": 100.0,
#     "legA": { "uiOutAmount": 100.05, "priceImpactPct": 0.012 }, # first swap
#     "legB": { "uiOutAmount":  99.98, "priceImpactPct": 0.013 }, # return swap
#     "roundtrip_final_amount": 99.98,
#     "roundtrip_cost_pct":      0.020   # 1 - (return-swap uiOut / start_amount) in percent
#   }
#
# Stderr:
#   "usage: ..."            -> bad arguments
#   "first_swap_failed: <msg>"  -> first-swap dry-run returned success=false or non-JSON
#   "return_swap_failed: <msg>" -> return-swap dry-run returned success=false or non-JSON
#   "parse_error: <msg>"    -> unexpected output shape
#
# Exit codes:
#   0  = OK
#   1  = bad usage
#   5  = parse failure
#   12 = first-swap dry-run failed
#   13 = return-swap dry-run failed
#
# Note on numbering: swap dry-run failures use 12/13 as distinct codes from
# the shared exit-code convention (where 2 = network / 3 = HTTP 4xx).
# Callers can route a `dry_run_failed:exit_12` cleanly as "byreal router rejected
# the swap" instead of "network glitch — retry later".
#
# This script produces the quote and accounting numbers. The caller compares
# them against max_per_leg_pi_pct and, only when explicitly supplied,
# max_roundtrip_cost_pct.

set -euo pipefail

input_mint=""
output_mint=""
start_amount=""
wallet=""
slippage_bps="100"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-mint)   input_mint="$2"; shift 2 ;;
    --output-mint)  output_mint="$2"; shift 2 ;;
    --start-amount) start_amount="$2"; shift 2 ;;
    --wallet)       wallet="$2"; shift 2 ;;
    --slippage-bps) slippage_bps="$2"; shift 2 ;;
    *) echo "usage: $(basename "$0") --input-mint X --output-mint Y --start-amount N --wallet W [--slippage-bps 100]" >&2; exit 1 ;;
  esac
done

if [[ -z "$input_mint" || -z "$output_mint" || -z "$start_amount" || -z "$wallet" ]]; then
  echo "usage: $(basename "$0") --input-mint X --output-mint Y --start-amount N --wallet W [--slippage-bps 100]" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v byreal-cli >/dev/null 2>&1; then
  echo "missing_command:byreal-cli" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

# Hold both swaps' raw output in tmpfiles so the Python parser can read them
# without exposing the content to shell expansion (byreal-cli output can contain
# $, backticks, or backslashes that would otherwise be interpolated by the shell).
tmp_a=$(mktemp)
tmp_b=$(mktemp)
trap 'rm -f "$tmp_a" "$tmp_b"' EXIT

# Run first-swap dry-run. byreal-cli prints a "[DRY RUN] No transaction will be
# executed" banner before the JSON; python parses past it by extracting the
# first JSON object.
set +e
byreal-cli swap execute \
  --input-mint "$input_mint" --output-mint "$output_mint" \
  --amount "$start_amount" --slippage "$slippage_bps" \
  --wallet-address "$wallet" --dry-run -o json > "$tmp_a" 2>&1
leg_a_exit=$?
set -e

if [[ $leg_a_exit -ne 0 ]]; then
  echo "first_swap_failed: byreal-cli exited $leg_a_exit" >&2
  cat "$tmp_a" >&2
  exit 12
fi

# extract_leg parses the wrapped byreal-cli JSON, distinguishing parse error vs
# swap failure (success:false) vs success. Reads from argv[1], writes JSON / sentinel
# to stdout, exits 0 always — caller branches on stdout content.
extract_leg() {
  PYTHONPATH="${script_dir}/lib${PYTHONPATH:+:$PYTHONPATH}" python3 - "$1" <<'PY'
import json, sys
from byreal_cli_json import extract_success_object_from_file

parsed = extract_success_object_from_file(sys.argv[1])
if parsed is None:
    print("__PARSE_FAIL__"); sys.exit(0)
if not parsed.get("success"):
    err = parsed.get("error", {}).get("message", "unknown")
    print(f"__LEG_FAIL__{err}"); sys.exit(0)
d = parsed.get("data", {})
# byreal-swap canonicalizes on uiOutAmount; if a future CLI version drops it,
# fail loud rather than silently falling back to outAmount (which is raw units
# and would corrupt all downstream math).
out_amt = d.get("uiOutAmount")
if out_amt is None:
    print("__PARSE_FAIL__"); sys.exit(0)
# priceImpactPct may be absent (Titan does not always return it). Pass through
# as null; the trading-comp pool gate treats missing impact as missing guard data.
pi = d.get("priceImpactPct")
print(json.dumps({"uiOutAmount": out_amt, "priceImpactPct": pi}))
PY
}

leg_a_json=$(extract_leg "$tmp_a")

if [[ "$leg_a_json" == "__PARSE_FAIL__" ]]; then
  echo "parse_error: first-swap dry-run output did not contain a parseable JSON object" >&2
  cat "$tmp_a" >&2
  exit 5
fi
if [[ "$leg_a_json" == __LEG_FAIL__* ]]; then
  echo "first_swap_failed: ${leg_a_json#__LEG_FAIL__}" >&2
  exit 12
fi

leg_a_ui_out=$(echo "$leg_a_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['uiOutAmount'])")

if [[ -z "$leg_a_ui_out" || "$leg_a_ui_out" == "None" ]]; then
  echo "parse_error: first-swap dry-run did not return uiOutAmount" >&2
  exit 5
fi

# Run return-swap dry-run with the first swap's output as input, swapping mint direction.
set +e
byreal-cli swap execute \
  --input-mint "$output_mint" --output-mint "$input_mint" \
  --amount "$leg_a_ui_out" --slippage "$slippage_bps" \
  --wallet-address "$wallet" --dry-run -o json > "$tmp_b" 2>&1
leg_b_exit=$?
set -e

if [[ $leg_b_exit -ne 0 ]]; then
  echo "return_swap_failed: byreal-cli exited $leg_b_exit" >&2
  cat "$tmp_b" >&2
  exit 13
fi

leg_b_json=$(extract_leg "$tmp_b")

if [[ "$leg_b_json" == "__PARSE_FAIL__" ]]; then
  echo "parse_error: return-swap dry-run output did not contain a parseable JSON object" >&2
  cat "$tmp_b" >&2
  exit 5
fi
if [[ "$leg_b_json" == __LEG_FAIL__* ]]; then
  echo "return_swap_failed: ${leg_b_json#__LEG_FAIL__}" >&2
  exit 13
fi

# Combine and compute roundtrip_cost_pct. Pass values via environment to avoid
# any shell expansion of the JSON strings inside the python heredoc.
export _LEG_A="$leg_a_json"
export _LEG_B="$leg_b_json"
export _START="$start_amount"
export _IN_MINT="$input_mint"
export _OUT_MINT="$output_mint"

python3 <<'PY'
import json, math, os, sys

def normalize_price_impact(raw):
    if raw is None or raw == "":
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return raw
    if not math.isfinite(value):
        return str(raw)
    return value

leg_a = json.loads(os.environ["_LEG_A"])
leg_b = json.loads(os.environ["_LEG_B"])
start = float(os.environ["_START"])
if not math.isfinite(start) or start <= 0:
    print("parse_error: start_amount must be > 0", file=sys.stderr); sys.exit(5)
first_out = float(leg_a["uiOutAmount"])
final = float(leg_b["uiOutAmount"])
if not math.isfinite(first_out) or first_out < 0:
    print("parse_error: first-swap dry-run returned invalid uiOutAmount", file=sys.stderr); sys.exit(5)
if not math.isfinite(final) or final < 0:
    print("parse_error: return-swap dry-run returned invalid uiOutAmount", file=sys.stderr); sys.exit(5)
cost_pct = (1.0 - final / start) * 100.0
out = {
    "input_mint": os.environ["_IN_MINT"],
    "output_mint": os.environ["_OUT_MINT"],
    "start_amount": start,
    "legA": {"uiOutAmount": first_out,
             "priceImpactPct": normalize_price_impact(leg_a["priceImpactPct"])},
    "legB": {"uiOutAmount": final,
             "priceImpactPct": normalize_price_impact(leg_b["priceImpactPct"])},
    "roundtrip_final_amount": final,
    "roundtrip_cost_pct": cost_pct,
}
print(json.dumps(out, indent=2))
PY
