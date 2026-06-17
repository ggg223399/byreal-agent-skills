#!/usr/bin/env bash
# Decide whether a wallet is ready to run cycles for selected pools, and
# if not, what pre-swap is needed per pool. Pure analysis — the caller is
# responsible for fetching balances (typically via agent-token wallet-info)
# and passing them in.
#
# The pre-swap target for each pool is plan-cycle.sh's `start_mint` —
# nothing more. plan-cycle already defaults to the stable side (USD1 /
# USDC / USDT), so the "prefer stable over SOL over non-stable" rule is
# encoded once, in plan-cycle, and reused here.
#
# Usage:
#   check-wallet.sh \
#     --wallet <addr> \
#     --campaign <campaign_type> \
#     --pools "USD1-USDC,WLFI-USDC" \
#     --per-swap-usd 100 \
#     --sol-balance 1.234 \
#     --token-balances '{"<mint>": <ui_balance>, ...}' \
#     [--gas-floor 0.02] \
#     [--start-mint "POOL=MINT"]...
#
# Stdout (JSON):
#   {
#     "wallet": "...",
#     "gas":   { "sol": 1.234, "floor": 0.02, "ok": true },
#     "pools": [
#       { "name": "USD1-USDC", "start_mint": "...", "needed_ui": 100,
#         "balance_ui": 250, "has_enough": true }
#     ],
#     "ready_pools":      ["USD1-USDC"],
#     "pre_swap_actions": [
#       { "pool": "WLFI-USDC", "target_mint": "EPjFWdd5...",
#         "needed_ui": 100, "balance_ui": 0 }
#     ],
#     "blockers": ["..."]
#   }
#
# Stderr:
#   "parse_error: <where>: <msg>"
#   "no_stable_pools:<pool1> <pool2>..."   (any pool's plan-cycle exited 7)
#   "start_mint_override_invalid:<value>"
#
# Exit:
#   0 = OK
#   1 = bad usage
#   5 = JSON parse failure
#   7 = at least one pool returned no_stable_side (output still written;
#         caller asks user for --start-mint per affected pool)

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

wallet=""
campaign=""
pools_csv=""
per_swap_usd=""
sol_balance=""
token_balances=""
gas_floor="0.02"
start_mint_overrides=()

usage() {
  echo "usage: $(basename "$0") --wallet W --campaign T --pools P1,P2 --per-swap-usd N --sol-balance N --token-balances JSON [--gas-floor 0.02] [--start-mint POOL=MINT]..." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet)         wallet="$2"; shift 2 ;;
    --campaign)       campaign="$2"; shift 2 ;;
    --pools)          pools_csv="$2"; shift 2 ;;
    --per-swap-usd)   per_swap_usd="$2"; shift 2 ;;
    --sol-balance)    sol_balance="$2"; shift 2 ;;
    --token-balances) token_balances="$2"; shift 2 ;;
    --gas-floor)      gas_floor="$2"; shift 2 ;;
    --start-mint)     start_mint_overrides+=("$2"); shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$wallet" || -z "$campaign" || -z "$pools_csv" || -z "$per_swap_usd" || -z "$sol_balance" || -z "$token_balances" ]] && usage

for override in "${start_mint_overrides[@]}"; do
  if [[ "$override" != *=* || -z "${override%%=*}" || -z "${override#*=}" ]]; then
    echo "start_mint_override_invalid:${override}" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run plan-cycle.sh once per pool, collecting outputs into a tmpfile so
# the python aggregator below can read everything without shell-escaping
# byreal-cli output through env vars.
plans_file=$(mktemp)
trap 'rm -f "$plans_file"' EXIT

IFS=',' read -ra pool_array <<< "$pools_csv"
no_stable=()

printf '[' > "$plans_file"
first=1
for raw_pool in "${pool_array[@]}"; do
  pool=$(echo "$raw_pool" | xargs)
  [[ -z "$pool" ]] && continue

  start_mint_override=""
  for override in "${start_mint_overrides[@]}"; do
    override_pool="${override%%=*}"
    override_mint="${override#*=}"
    if [[ "$override_pool" == "$pool" ]]; then
      start_mint_override="$override_mint"
    fi
  done

  pc_cmd=("$script_dir/plan-cycle.sh" --pool "$pool" --campaign "$campaign" --per-swap-usd "$per_swap_usd")
  if [[ -n "$start_mint_override" ]]; then
    pc_cmd+=(--start-mint "$start_mint_override")
  fi

  set +e
  pc_out=$("${pc_cmd[@]}" 2>/dev/null)
  pc_exit=$?
  set -e

  if [[ $first -eq 0 ]]; then printf ',' >> "$plans_file"; fi
  first=0

  pool_json=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$pool")
  if [[ $pc_exit -eq 0 ]]; then
    printf '{"pool":%s,"plan":%s}' "$pool_json" "$pc_out" >> "$plans_file"
  else
    [[ $pc_exit -eq 7 ]] && no_stable+=("$pool")
    printf '{"pool":%s,"plan":null,"plan_exit":%d}' "$pool_json" "$pc_exit" >> "$plans_file"
  fi
done
printf ']' >> "$plans_file"

export _PLANS_FILE="$plans_file"
export _WALLET="$wallet"
export _SOL="$sol_balance"
export _GAS_FLOOR="$gas_floor"
export _TOKEN_BAL="$token_balances"

python3 <<'PY'
import json, math, os, sys

NATIVE_SOL_MINTS = {"So11111111111111111111111111111111111111112"}


def finite_nonnegative(value, label):
    try:
        number = float(value)
    except Exception:
        raise ValueError(f"{label} must be numeric")
    if not math.isfinite(number) or number < 0:
        raise ValueError(f"{label} must be a finite nonnegative number")
    return number

try:
    plans = json.load(open(os.environ["_PLANS_FILE"]))
except Exception as e:
    print(f"parse_error: plans: {e}", file=sys.stderr); sys.exit(5)
try:
    balances = json.loads(os.environ["_TOKEN_BAL"])
    if not isinstance(balances, dict):
        raise ValueError("must be a JSON object")
except Exception as e:
    print(f"parse_error: --token-balances: {e}", file=sys.stderr); sys.exit(5)

try:
    sol = finite_nonnegative(os.environ["_SOL"], "--sol-balance")
    floor = finite_nonnegative(os.environ["_GAS_FLOOR"], "--gas-floor")
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)
gas_ok = sol >= floor

pools_out, ready, preswap, blockers = [], [], [], []

for entry in plans:
    pool = entry["pool"]
    p = entry.get("plan")
    if p is None:
        pools_out.append({"name": pool, "skipped": True, "plan_exit": entry.get("plan_exit")})
        blockers.append(f"{pool}: plan-cycle exit {entry.get('plan_exit')}")
        continue
    start_mint = p["start_mint"]
    try:
        needed = finite_nonnegative(p["per_swap_in_start_units"], f"{pool}: per_swap_in_start_units")
        bal = sol if start_mint in NATIVE_SOL_MINTS else finite_nonnegative(balances.get(start_mint, 0), f"balance for {start_mint}")
    except Exception as e:
        print(f"parse_error: {e}", file=sys.stderr)
        sys.exit(5)
    has = bal >= needed
    pools_out.append({
        "name": pool,
        "start_mint": start_mint,
        "needed_ui": needed,
        "balance_ui": bal,
        "has_enough": has,
    })
    if has:
        ready.append(pool)
    else:
        preswap.append({
            "pool": pool,
            "target_mint": start_mint,
            "needed_ui": needed,
            "balance_ui": bal,
        })

if not gas_ok:
    blockers.append(f"SOL balance {sol} < gas_floor {floor}")

out = {
    "wallet":            os.environ["_WALLET"],
    "gas":               {"sol": sol, "floor": floor, "ok": gas_ok},
    "pools":             pools_out,
    "ready_pools":       ready,
    "pre_swap_actions":  preswap,
    "blockers":          blockers,
}
json.dump(out, sys.stdout, indent=2)
print()
PY

if [[ ${#no_stable[@]} -gt 0 ]]; then
  echo "no_stable_pools:${no_stable[*]}" >&2
  exit 7
fi
