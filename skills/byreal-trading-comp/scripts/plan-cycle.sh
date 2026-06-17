#!/usr/bin/env bash
# Plan one round-trip cycle: pick which mint to start from and convert a USD
# size into UI units of that mint. Pure data transform — no network calls
# beyond reusing fetch-pools.sh.
#
# Encodes the sizing rules so the LLM never does the arithmetic. The output is
# what dry-run-cycle.sh and the live --execute calls need as inputs.
#
# Usage:
#   plan-cycle.sh --pool <name> --campaign <type> --per-swap-usd N
#                 [--start-mint <mint>]   # override the default-start-side rule
#
# Defaults for picking the start side (when --start-mint is not given):
#   1. If exactly one side of the pool is a recognized USD stable
#      (USDC / USD1 / USDT by symbol), start from the stable. USD->units is
#      trivial and the wallet most likely holds the stable already.
#   2. If both sides are stables, pick alphabetical-by-symbol for determinism.
#   3. If neither side is a stable, exit 7 — caller must supply --start-mint
#      AND provide size directly in start-mint units (this script can't safely
#      derive USD->units without a stable-anchored price).
#
# Stdout (JSON):
#   {
#     "pool_name": "WLFI-USDC",
#     "pool_address": "...",
#     "start_mint":   "...",
#     "other_mint":   "...",
#     "per_swap_in_start_units": 1234.5,
#     "fee_rate_pct": 0.5,
#     "tvl_usd":      138900.12,
#     "pool_price":   0.081,
#     "price_basis":  "mintB_per_mintA",
#     "start_usd_price": 1.0,            # USD value of 1 start-mint UI unit
#     "other_usd_price": 0.0668,         # USD value of 1 other-mint UI unit;
#                                        # callers use this to USD-price return-swap input
#                                        # (which is first-swap output, denominated in other-mint).
#     "conversion": "stable_start" | "nonstable_start_via_pool_price"
#   }
#
# Stderr:  "pool_missing:<name>"               (pool not in fetch-pools output)
#          "start_mint_invalid:<mint>"         (override is not pool.mintA/mintB)
#          "no_stable_side"                    (rule 3 — caller must override)
#          "fetch_pools_failed:exit_<code>"
#          "parse_error:<msg>"
#
# Exit:    0 = OK
#          1 = bad usage
#          2 = fetch-pools failed (network/HTTP)
#          5 = parse failure
#          6 = campaign config missing (propagated)
#          7 = start side missing/invalid — explicit --start-mint required

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

pool=""
campaign=""
per_swap_usd=""
start_mint=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pool)         pool="$2"; shift 2 ;;
    --campaign)     campaign="$2"; shift 2 ;;
    --per-swap-usd) per_swap_usd="$2"; shift 2 ;;
    --start-mint)   start_mint="$2"; shift 2 ;;
    *) echo "usage: $(basename "$0") --pool NAME --campaign TYPE --per-swap-usd N [--start-mint MINT]" >&2; exit 1 ;;
  esac
done

if [[ -z "$pool" || -z "$campaign" || -z "$per_swap_usd" ]]; then
  echo "usage: $(basename "$0") --pool NAME --campaign TYPE --per-swap-usd N [--start-mint MINT]" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fp_err=$(mktemp)
trap 'rm -f "$fp_err"' EXIT

set +e
pools_json=$("$script_dir/fetch-pools.sh" --campaign "$campaign" 2>"$fp_err")
fp_exit=$?
set -e

if [[ $fp_exit -ne 0 ]]; then
  cat "$fp_err" >&2 || true
  echo "fetch_pools_failed:exit_${fp_exit}" >&2
  # Propagate fetch-pools' own exit codes so callers can distinguish.
  case "$fp_exit" in
    2|3|4) exit 2 ;;
    5)     exit 5 ;;
    6)     exit 6 ;;
    *)     exit 2 ;;
  esac
fi

export _POOLS_JSON="$pools_json"
export _POOL="$pool"
export _PSU="$per_swap_usd"
export _START_OVERRIDE="$start_mint"

python3 <<'PY'
import json, os, sys

STABLE_SYMBOLS = {"USDC", "USD1", "USDT", "USDS"}

try:
    pools = json.loads(os.environ["_POOLS_JSON"])
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)

pool_name = os.environ["_POOL"]
if pool_name not in pools:
    print(f"pool_missing:{pool_name}", file=sys.stderr)
    sys.exit(5)

p = pools[pool_name]
mintA, mintB = p["mintA"], p["mintB"]
symA, symB   = p.get("symbolA") or "", p.get("symbolB") or ""
price        = float(p["price"])  # mintB per mintA, per Byreal pools API

override = os.environ["_START_OVERRIDE"].strip()
if override:
    if override not in (mintA, mintB):
        print(f"start_mint_invalid:{override}", file=sys.stderr)
        sys.exit(7)
    start_mint = override
else:
    a_stable = symA.upper() in STABLE_SYMBOLS
    b_stable = symB.upper() in STABLE_SYMBOLS
    if a_stable and not b_stable:
        start_mint = mintA
    elif b_stable and not a_stable:
        start_mint = mintB
    elif a_stable and b_stable:
        start_mint = mintA if symA.upper() <= symB.upper() else mintB
    else:
        print("no_stable_side", file=sys.stderr)
        sys.exit(7)

# Compute per_swap_in_start_units. The pool's reported price is mintB per mintA.
# If start_mint is mintA: 1 mintA = `price` mintB. USD price of mintA = price (if mintB is stable) or 1/price-via-stable.
# Since we only enter the non-stable branch when exactly one side is a stable,
# the math collapses cleanly:
psu = float(os.environ["_PSU"])
other_mint = mintB if start_mint == mintA else mintA

start_is_stable = (start_mint == mintA and symA.upper() in STABLE_SYMBOLS) or \
                  (start_mint == mintB and symB.upper() in STABLE_SYMBOLS)

if start_is_stable:
    units = psu                  # 1 stable ~ $1
    start_usd_price = 1.0
    conversion = "stable_start"
else:
    # Start side is the non-stable; other side is the stable.
    # If start_mint == mintA (non-stable), price (=mintB/mintA) is start-token's USD price.
    # If start_mint == mintB (non-stable), USD price of mintB = 1 / price.
    if start_mint == mintA:
        start_usd_price = price
    else:
        start_usd_price = (1.0 / price) if price else 0.0
    if start_usd_price <= 0:
        print("parse_error: derived USD price <= 0", file=sys.stderr)
        sys.exit(5)
    units = psu / start_usd_price
    conversion = "nonstable_start_via_pool_price"

# Derive other_usd_price the same way. We're guaranteed exactly one stable side
# by the start-selection rule above (no_stable_side exits 7 earlier), so:
#   - if other_mint is mintA: other_usd_price = pool.price (mintB stable, so 1 mintA = price mintB = $price)
#   - if other_mint is mintB: other_usd_price = 1/pool.price (mintA stable, so 1 mintB = 1/price mintA = $1/price)
# When both sides are stable, both prices are 1.0.
a_stable = symA.upper() in STABLE_SYMBOLS
b_stable = symB.upper() in STABLE_SYMBOLS
if a_stable and b_stable:
    other_usd_price = 1.0
else:
    if other_mint == mintA:
        other_usd_price = price
    else:
        other_usd_price = (1.0 / price) if price else 0.0
    if other_usd_price <= 0:
        print("parse_error: derived other_usd_price <= 0", file=sys.stderr)
        sys.exit(5)

out = {
    "pool_name": pool_name,
    "pool_address": p["poolAddress"],
    "start_mint": start_mint,
    "other_mint": other_mint,
    "per_swap_in_start_units": units,
    "fee_rate_pct": p["feeRatePct"],
    "tvl_usd": p["tvl"],
    "pool_price": price,
    "price_basis": "mintB_per_mintA",
    "start_usd_price": start_usd_price,
    "other_usd_price": other_usd_price,
    "conversion": conversion,
}
json.dump(out, sys.stdout, indent=2)
print()
PY
