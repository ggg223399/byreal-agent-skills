#!/usr/bin/env bash
# Fetch a page of the leaderboard for a Byreal trading competition.
#
# Used at setup confirm to estimate "what credited-volume gap is needed to gain
# N ranks" and by the optional rank-delta projection. The skill never needs the full list —
# one page near the wallet's current rank is enough.
#
# Usage:   fetch-leaderboard.sh <campaign_type> [page] [pageSize]
#          page defaults to 1, pageSize defaults to 20 (matches the API default).
# Env:     BYREAL_CONTEST_BASE  (default: https://api2.byreal.io/byreal/api/dex/v2/contest)
# Stdout:
#   {
#     "campaignType": "wlfi_season_1",
#     "page": 1, "pageSize": 20, "total": <int>,
#     "rows": [
#       { "rankNo": 1, "userAddress": "...", "creditedVolume": 1234567.89, "estimatedReward": 50000 },
#       ...
#     ]
#   }
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

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $(basename "$0") <campaign_type> [page] [pageSize]" >&2
  exit 1
fi

campaign_type="$1"
page="${2:-1}"
page_size="${3:-20}"

base="${BYREAL_CONTEST_BASE:-https://api2.byreal.io/byreal/api/dex/v2/contest}"
url="${base}/rank/list?campaignType=${campaign_type}&page=${page}&pageSize=${page_size}"

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

export _RESP="$tmp"
export _CT="$campaign_type"
export _PAGE="$page"
export _PSIZE="$page_size"

python3 <<'PY'
import json, os, sys

def unwrap_data(body):
    if "code" in body:
        if body.get("code") != 0:
            print(f"api_error:{body.get('code')}", file=sys.stderr)
            sys.exit(5)
        return body.get("data") or {}

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
        return result.get("data") or {}

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
    with open(os.environ["_RESP"]) as f:
        body = json.load(f)
    data = unwrap_data(body)
    # The contest API has historically wrapped paginated results as
    # { records: [...], total: N } under data; tolerate either shape.
    rows = data.get("records") or data.get("list") or data.get("rows") or []
    total = data.get("total") or data.get("count") or len(rows)
    for row in rows:
        if not isinstance(row, dict):
            continue
        if "rankNo" in row:
            row["rankNo"] = normalize_number(row["rankNo"])
        api_volume_key = "".join(("g", "m", "v"))
        if api_volume_key in row:
            row["creditedVolume"] = normalize_number(row.pop(api_volume_key))
        if "estimatedReward" in row:
            row["estimatedReward"] = normalize_number(row["estimatedReward"])
    out = {
        "campaignType": os.environ["_CT"],
        "page": int(os.environ["_PAGE"]),
        "pageSize": int(os.environ["_PSIZE"]),
        "total": int(total),
        "rows": rows,
    }
    json.dump(out, sys.stdout, indent=2)
    print()
except SystemExit:
    raise
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)
PY
