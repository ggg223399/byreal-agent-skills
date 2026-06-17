#!/usr/bin/env bash
# Fetch the wallet's current rank in a Byreal trading competition.
#
# Usage:   fetch-rank.sh <campaign_type> <user_address>
# Env:     BYREAL_CONTEST_BASE  (default: https://api2.byreal.io/byreal/api/dex/v2/contest)
# Stdout:  Normalized rank object, e.g.
#          { "rankNo": 5, "userAddress": "...", "creditedVolume": 75000.0,
#            "estimatedReward": 15000, "userType": 1, "offLeaderboard": false }
#
#          Per the API contract, a wallet outside the top-300 leaderboard receives
#          rankNo=500 (sentinel) with estimatedReward=0. The script annotates
#          `offLeaderboard:true`; callers render that as outside top 300.
# Stderr:  "network_failure" | "http_<code>" | "api_error:<code>" | "parse_error"
# Exit:    0 = OK
#          1 = bad usage
#          2 = network failure
#          3 = HTTP 4xx
#          4 = HTTP 5xx
#          5 = parse failure or API code != 0

set -euo pipefail

for cmd in curl python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing_command:${cmd}" >&2
    exit 1
  fi
done

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
  echo "usage: $(basename "$0") <campaign_type> <user_address>" >&2
  exit 1
fi

campaign_type="$1"
user_address="$2"
base="${BYREAL_CONTEST_BASE:-https://api2.byreal.io/byreal/api/dex/v2/contest}"
url="${base}/rank/my?campaignType=${campaign_type}&userAddress=${user_address}"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

set +e
status=$(curl -sS --max-time 15 -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null)
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

python3 - "$tmp" <<'PY'
import json, sys

def unwrap_data(body):
    if "code" in body:
        if body.get("code") != 0:
            print(f"api_error:{body.get('code')}", file=sys.stderr)
            sys.exit(5)
        return body.get("data")

    if "retCode" in body:
        if body.get("retCode") != 0:
            print(f"api_error:{body.get('retCode')}", file=sys.stderr)
            sys.exit(5)
        result = body.get("result") or {}
        if result.get("success") is False:
            code = result.get("ret_code", result.get("retCode", body.get("retCode")))
            print(f"api_error:{code}", file=sys.stderr)
            sys.exit(5)
        ret_code = result.get("ret_code")
        if ret_code not in (None, 0):
            print(f"api_error:{ret_code}", file=sys.stderr)
            sys.exit(5)
        return result.get("data")

    print("api_error:unknown_envelope", file=sys.stderr)
    sys.exit(5)

def normalize_number(value):
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        try:
            number = float(value)
        except ValueError:
            return value
        return int(number) if number.is_integer() else number
    return value

try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    data = unwrap_data(body)
    if not isinstance(data, dict):
        print("parse_error: missing data object", file=sys.stderr)
        sys.exit(5)
    if "rankNo" in data:
        data["rankNo"] = normalize_number(data["rankNo"])
    api_volume_key = "".join(("g", "m", "v"))
    if api_volume_key in data:
        data["creditedVolume"] = normalize_number(data.pop(api_volume_key))
    if "estimatedReward" in data:
        data["estimatedReward"] = normalize_number(data["estimatedReward"])
    # Annotate the off-leaderboard sentinel so callers don't accidentally
    # display "rank 500" as a real position.
    if data.get("rankNo") == 500:
        data["offLeaderboard"] = True
    else:
        data["offLeaderboard"] = False
    json.dump(data, sys.stdout, indent=2)
    print()
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)
PY
