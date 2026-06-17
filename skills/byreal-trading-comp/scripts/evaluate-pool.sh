#!/usr/bin/env bash
# Evaluate whether one pool should run for the next cycle.
#
# This is the composition layer for the shared pool gate:
#   plan-cycle.sh -> TVL size cap -> dry-run-cycle.sh -> threshold decision
#
# Usage:
#   evaluate-pool.sh \
#     --pool <name> --campaign <campaign_type> --per-swap-usd N --wallet W \
#     [--start-mint M] [--slippage-bps 100] \
#     [--max-per-leg-pi-pct 2.0] [--max-per-swap-loss-pct 2.0] [--max-roundtrip-cost-pct N] \
#     [--max-per-swap-pct-of-tvl 0.05] [--min-pool-tvl-usd N]
#
# Stdout (JSON):
#   {
#     "pool_name": "USD1-USDC",
#     "decision": "run" | "skip",
#     "reason": null | "tvl=..." | "dry_run_failed:exit_12" | "missing_first_swap_priceImpactPct" | "invalid_first_swap_priceImpactPct" | "first_swap_pi=...",
#     "requested_per_swap_usd": 1000,
#     "effective_per_swap_usd": 1000,
#     "capped": false,
#     "cap_usd": 42000,
#     "thresholds": {...},
#     "plan": {...},
#     "dry_run_result": {...} | null,
#     "dry_run_error": null | "..."
#   }
#
# Exit:
#   0 = JSON decision written
#   1 = bad usage / invalid threshold
#   2 = plan-cycle network/HTTP failure
#   5 = parse failure
#   6 = campaign config missing
#   7 = plan-cycle cannot derive a USD price without --start-mint

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

pool=""
campaign=""
per_swap_usd=""
wallet=""
start_mint=""
slippage_bps="100"
max_per_leg_pi_pct="2.0"
max_roundtrip_cost_pct=""
max_per_swap_pct_of_tvl="0.05"
min_pool_tvl_usd=""

usage() {
  echo "usage: $(basename "$0") --pool NAME --campaign TYPE --per-swap-usd N --wallet W [--start-mint MINT] [--slippage-bps 100] [--max-per-leg-pi-pct 2.0|--max-per-swap-loss-pct 2.0] [--max-roundtrip-cost-pct N] [--max-per-swap-pct-of-tvl 0.05] [--min-pool-tvl-usd N]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pool)                     pool="$2"; shift 2 ;;
    --campaign)                 campaign="$2"; shift 2 ;;
    --per-swap-usd)             per_swap_usd="$2"; shift 2 ;;
    --wallet)                   wallet="$2"; shift 2 ;;
    --start-mint)               start_mint="$2"; shift 2 ;;
    --slippage-bps)             slippage_bps="$2"; shift 2 ;;
    --max-per-leg-pi-pct|--max-per-swap-loss-pct)
                                  max_per_leg_pi_pct="$2"; shift 2 ;;
    --max-roundtrip-cost-pct)   max_roundtrip_cost_pct="$2"; shift 2 ;;
    --max-per-swap-pct-of-tvl)  max_per_swap_pct_of_tvl="$2"; shift 2 ;;
    --min-pool-tvl-usd)         min_pool_tvl_usd="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$pool" || -z "$campaign" || -z "$per_swap_usd" || -z "$wallet" ]] && usage

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plan_tmp=$(mktemp)
plan_err=$(mktemp)
dry_tmp=$(mktemp)
dry_err=$(mktemp)
meta_tmp=$(mktemp)
trap 'rm -f "$plan_tmp" "$plan_err" "$dry_tmp" "$dry_err" "$meta_tmp"' EXIT

plan_cmd=("$script_dir/plan-cycle.sh" --pool "$pool" --campaign "$campaign" --per-swap-usd "$per_swap_usd")
if [[ -n "$start_mint" ]]; then
  plan_cmd+=(--start-mint "$start_mint")
fi

set +e
"${plan_cmd[@]}" > "$plan_tmp" 2> "$plan_err"
plan_exit=$?
set -e

if [[ $plan_exit -ne 0 ]]; then
  cat "$plan_err" >&2
  exit "$plan_exit"
fi

export _PLAN="$plan_tmp"
export _POOL="$pool"
export _REQUESTED_USD="$per_swap_usd"
export _MAX_PCT_TVL="$max_per_swap_pct_of_tvl"
export _MAX_PI="$max_per_leg_pi_pct"
export _MAX_RT="$max_roundtrip_cost_pct"
export _MIN_TVL="$min_pool_tvl_usd"

python3 - "$meta_tmp" <<'PY'
import json, math, os, sys

try:
    plan = json.load(open(os.environ["_PLAN"]))
    requested = float(os.environ["_REQUESTED_USD"])
    max_pct_tvl = float(os.environ["_MAX_PCT_TVL"])
    max_pi = float(os.environ["_MAX_PI"])
    max_rt_raw = os.environ["_MAX_RT"].strip()
    max_rt = float(max_rt_raw) if max_rt_raw else None
    min_tvl_raw = os.environ["_MIN_TVL"].strip()
    min_tvl = float(min_tvl_raw) if min_tvl_raw else None
    tvl = float(plan["tvl_usd"])
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)

if (
    not math.isfinite(requested) or requested <= 0
    or not math.isfinite(tvl)
    or not math.isfinite(max_pct_tvl) or max_pct_tvl <= 0
    or not math.isfinite(max_pi) or max_pi < 0
    or (max_rt is not None and (not math.isfinite(max_rt) or max_rt < 0))
    or (min_tvl is not None and (not math.isfinite(min_tvl) or min_tvl < 0))
):
    print("invalid_threshold", file=sys.stderr)
    sys.exit(1)

cap_usd = tvl * max_pct_tvl
effective = min(requested, cap_usd)
out = {
    "cap_usd": cap_usd,
    "effective_per_swap_usd": effective,
    "capped": effective < requested,
    "tvl_usd": tvl,
}
json.dump(out, open(sys.argv[1], "w"))
PY

effective_per_swap_usd=$(python3 - "$meta_tmp" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["effective_per_swap_usd"])
PY
)

is_capped=$(python3 - "$meta_tmp" <<'PY'
import json, sys
print("1" if json.load(open(sys.argv[1]))["capped"] else "0")
PY
)

if [[ "$is_capped" == "1" ]]; then
  plan_cmd=("$script_dir/plan-cycle.sh" --pool "$pool" --campaign "$campaign" --per-swap-usd "$effective_per_swap_usd")
  if [[ -n "$start_mint" ]]; then
    plan_cmd+=(--start-mint "$start_mint")
  fi

  set +e
  "${plan_cmd[@]}" > "$plan_tmp" 2> "$plan_err"
  plan_exit=$?
  set -e

  if [[ $plan_exit -ne 0 ]]; then
    cat "$plan_err" >&2
    exit "$plan_exit"
  fi
fi

tvl_decision=$(python3 - "$plan_tmp" "$meta_tmp" <<'PY'
import json, os, sys
plan = json.load(open(sys.argv[1]))
min_tvl_raw = os.environ["_MIN_TVL"].strip()
if not min_tvl_raw:
    print("")
    raise SystemExit
min_tvl = float(min_tvl_raw)
if float(plan["tvl_usd"]) < min_tvl:
    print(f"tvl={plan['tvl_usd']} < min={min_tvl}")
else:
    print("")
PY
)

if [[ -n "$tvl_decision" ]]; then
  export _TVL_REASON="$tvl_decision"
  python3 - "$plan_tmp" "$meta_tmp" <<'PY'
import json, os, sys
plan = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
out = {
    "pool_name": os.environ["_POOL"],
    "decision": "skip",
    "reason": os.environ["_TVL_REASON"],
    "requested_per_swap_usd": float(os.environ["_REQUESTED_USD"]),
    "effective_per_swap_usd": float(meta["effective_per_swap_usd"]),
    "capped": bool(meta["capped"]),
    "cap_usd": float(meta["cap_usd"]),
    "thresholds": {
        "max_per_leg_pi_pct": float(os.environ["_MAX_PI"]),
        "max_roundtrip_cost_pct": (float(os.environ["_MAX_RT"]) if os.environ["_MAX_RT"].strip() else None),
        "max_per_swap_pct_of_tvl": float(os.environ["_MAX_PCT_TVL"]),
        "min_pool_tvl_usd": (float(os.environ["_MIN_TVL"]) if os.environ["_MIN_TVL"].strip() else None),
    },
    "plan": plan,
    "dry_run_result": None,
    "dry_run_error": None,
}
print(json.dumps(out, indent=2))
PY
  exit 0
fi

readarray -t dry_args < <(python3 - "$plan_tmp" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
print(plan["start_mint"])
print(plan["other_mint"])
print(plan["per_swap_in_start_units"])
PY
)

set +e
"$script_dir/dry-run-cycle.sh" \
  --input-mint "${dry_args[0]}" --output-mint "${dry_args[1]}" \
  --start-amount "${dry_args[2]}" --wallet "$wallet" \
  --slippage-bps "$slippage_bps" > "$dry_tmp" 2> "$dry_err"
dry_exit=$?
set -e

if [[ $dry_exit -ne 0 ]]; then
  export _DRY_EXIT="$dry_exit"
  python3 - "$plan_tmp" "$meta_tmp" "$dry_err" <<'PY'
import json, os, sys
plan = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
err = open(sys.argv[3]).read().strip()
out = {
    "pool_name": os.environ["_POOL"],
    "decision": "skip",
    "reason": f"dry_run_failed:exit_{os.environ['_DRY_EXIT']}",
    "requested_per_swap_usd": float(os.environ["_REQUESTED_USD"]),
    "effective_per_swap_usd": float(meta["effective_per_swap_usd"]),
    "capped": bool(meta["capped"]),
    "cap_usd": float(meta["cap_usd"]),
    "thresholds": {
        "max_per_leg_pi_pct": float(os.environ["_MAX_PI"]),
        "max_roundtrip_cost_pct": (float(os.environ["_MAX_RT"]) if os.environ["_MAX_RT"].strip() else None),
        "max_per_swap_pct_of_tvl": float(os.environ["_MAX_PCT_TVL"]),
        "min_pool_tvl_usd": (float(os.environ["_MIN_TVL"]) if os.environ["_MIN_TVL"].strip() else None),
    },
    "plan": plan,
    "dry_run_result": None,
    "dry_run_error": err or None,
}
print(json.dumps(out, indent=2))
PY
  exit 0
fi

python3 - "$plan_tmp" "$meta_tmp" "$dry_tmp" <<'PY'
import json, math, os, sys

plan = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
dry = json.load(open(sys.argv[3]))
max_pi = float(os.environ["_MAX_PI"])
max_rt_raw = os.environ["_MAX_RT"].strip()
max_rt = float(max_rt_raw) if max_rt_raw else None

decision = "run"
reason = None

def read_price_impact(raw, label):
    if raw is None or raw == "":
        return None, f"missing_{label}_priceImpactPct"
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None, f"invalid_{label}_priceImpactPct"
    if not math.isfinite(value):
        return None, f"invalid_{label}_priceImpactPct"
    return value, None

leg_a_pi, leg_a_pi_error = read_price_impact(dry.get("legA", {}).get("priceImpactPct"), "first_swap")
leg_b_pi, leg_b_pi_error = read_price_impact(dry.get("legB", {}).get("priceImpactPct"), "return_swap")
roundtrip = dry.get("roundtrip_cost_pct")

if leg_a_pi_error:
    decision = "skip"
    reason = leg_a_pi_error
elif leg_b_pi_error:
    decision = "skip"
    reason = leg_b_pi_error
elif leg_a_pi > max_pi:
    decision = "skip"
    reason = f"first_swap_pi={leg_a_pi} > max={max_pi}"
elif leg_b_pi > max_pi:
    decision = "skip"
    reason = f"return_swap_pi={leg_b_pi} > max={max_pi}"
elif max_rt is not None and roundtrip is not None and float(roundtrip) > max_rt:
    decision = "skip"
    reason = f"roundtrip={float(roundtrip)}% > max={max_rt}%"

out = {
    "pool_name": os.environ["_POOL"],
    "decision": decision,
    "reason": reason,
    "requested_per_swap_usd": float(os.environ["_REQUESTED_USD"]),
    "effective_per_swap_usd": float(meta["effective_per_swap_usd"]),
    "capped": bool(meta["capped"]),
    "cap_usd": float(meta["cap_usd"]),
    "thresholds": {
        "max_per_leg_pi_pct": max_pi,
        "max_roundtrip_cost_pct": max_rt,
        "max_per_swap_pct_of_tvl": float(os.environ["_MAX_PCT_TVL"]),
        "min_pool_tvl_usd": (float(os.environ["_MIN_TVL"]) if os.environ["_MIN_TVL"].strip() else None),
    },
    "plan": plan,
    "dry_run_result": dry,
    "dry_run_error": None,
}
print(json.dumps(out, indent=2))
PY
