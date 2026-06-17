#!/usr/bin/env bash
# Discover the eligible-pool subset for a Byreal trading campaign from the live
# pools list, using the resolved local campaign JSON as the source of truth for
# "which mint pairs count this season."
#
# Pool addresses can migrate; the mint set is authoritative.
#
# Usage:   fetch-pools.sh --campaign <campaign_type>
# Env:     BYREAL_CAMPAIGN_CONFIG_DIR  optional directory override for <campaign>.json lookup
#          BYREAL_POOLS_URL            default: https://api2.byreal.io/byreal/api/dex/v2/pools/info/list?page=1&pageSize=500
# Stdout:  JSON object keyed by pair name as defined in the campaign config, e.g.
#          {
#            "USD1-USDC": {
#              "poolAddress": "...", "mintA": "...", "mintB": "...",
#              "decA": 6, "decB": 6,
#              "feeRate": 100, "feeRatePct": 0.01,
#              "tvl": 201329.39, "vol24h": 18814.41, "price": 0.9992,
#              "symbolA": "USD1", "symbolB": "USDC"
#            },
#            ...
#          }
#          Pairs that exist in the config but are absent from the live API are
#          omitted from stdout (callers detect "delisted" via the stderr line).
# Stderr:  "config_missing:<path>" | "config_dir_missing:<path>" | "config_invalid:<msg>" |
#          "network_failure" | "http_<code>" | "parse_error" |
#          "missing_pair:<key>" per configured pair not found in the API.
# Exit:    0 = at least one configured pair resolved
#          1 = bad usage
#          2 = network/timeout failure
#          3 = HTTP 4xx
#          4 = HTTP 5xx
#          5 = parse failure or zero configured pairs matched
#          6 = campaign config file missing or invalid

set -euo pipefail

for cmd in curl python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing_command:${cmd}" >&2
    exit 1
  fi
done

campaign=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --campaign) campaign="$2"; shift 2 ;;
    *) echo "usage: $(basename "$0") --campaign <campaign_type>" >&2; exit 1 ;;
  esac
done

if [[ -z "$campaign" ]]; then
  echo "usage: $(basename "$0") --campaign <campaign_type>" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

config_err=$(mktemp)
tmp=""
trap 'rm -f "$config_err" "${tmp:-}"' EXIT

set +e
config_file=$("$script_dir/validate-campaign-config.sh" --resolve-path "$campaign" 2>"$config_err")
config_exit=$?
set -e

if [[ $config_exit -ne 0 ]]; then
  cat "$config_err" >&2 || true
  exit 6
fi

url="${BYREAL_POOLS_URL:-https://api2.byreal.io/byreal/api/dex/v2/pools/info/list?page=1&pageSize=500}"

tmp=$(mktemp)

set +e
status=$(curl -sS --max-time 20 -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null)
curl_exit=$?
set -e

if [[ $curl_exit -ne 0 || -z "$status" || "$status" == "000" ]]; then
  echo "network_failure" >&2
  exit 2
fi

case "$status" in
  2*)  : ;;
  4*)  echo "http_${status}" >&2; exit 3 ;;
  5*)  echo "http_${status}" >&2; exit 4 ;;
  *)   echo "http_${status}" >&2; exit 4 ;;
esac

export _POOLS_RESPONSE="$tmp"
export _CAMPAIGN_CONFIG="$config_file"

python3 <<'PY'
import json, os, sys

config_path = os.environ["_CAMPAIGN_CONFIG"]
pools_path  = os.environ["_POOLS_RESPONSE"]

try:
    with open(config_path) as f:
        config = json.load(f)
    eligible = config["eligible_pools"]
    whitelist = {p["name"]: frozenset(p["mints"]) for p in eligible}
    if not whitelist:
        print("config_invalid: empty eligible_pools", file=sys.stderr)
        sys.exit(6)
except KeyError as e:
    print(f"config_invalid: missing key {e}", file=sys.stderr)
    sys.exit(6)
except Exception as e:
    print(f"config_invalid: {e}", file=sys.stderr)
    sys.exit(6)

try:
    with open(pools_path) as f:
        body = json.load(f)
    records = body["result"]["data"]["records"]
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)

out = {}
for r in records:
    try:
        mA = r["mintA"]["mintInfo"]
        mB = r["mintB"]["mintInfo"]
        pair_mints = frozenset({mA["address"], mB["address"]})
    except (KeyError, TypeError):
        continue
    for key, mints in whitelist.items():
        if pair_mints == mints:
            fee_rate = int(r["feeRate"]["fixFeeRate"])
            out[key] = {
                "poolAddress": r["poolAddress"],
                "mintA": mA["address"],
                "mintB": mB["address"],
                "decA": int(mA["decimals"]),
                "decB": int(mB["decimals"]),
                "symbolA": mA.get("symbol"),
                "symbolB": mB.get("symbol"),
                "feeRate": fee_rate,
                "feeRatePct": fee_rate / 10000.0,
                "tvl": float(r["tvl"]),
                "vol24h": float(r["volumeUsd24h"]),
                "price": float(r["price"]),
            }
            break

for key in whitelist:
    if key not in out:
        print(f"missing_pair:{key}", file=sys.stderr)

if not out:
    print("parse_error: zero configured pairs found in API response", file=sys.stderr)
    sys.exit(5)

json.dump(out, sys.stdout, indent=2)
print()
PY
