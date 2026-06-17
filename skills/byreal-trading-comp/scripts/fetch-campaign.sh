#!/usr/bin/env bash
# Fetch Byreal trading-competition campaign metadata.
#
# Usage:   fetch-campaign.sh <campaign_type>
# Env:     BYREAL_CONTEST_BASE  (default: https://api2.byreal.io/byreal/api/dex/v2/contest)
# Stdout:  The "data" object from the API, e.g.
#          { "campaignType": "wlfi_season_1", "name": "...",
#            "startTime": 1717200000000, "endTime": 1717804800000 }
#          Caller derives status (pending / live / ended) by comparing now to start/end.
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

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "usage: $(basename "$0") <campaign_type>" >&2
  exit 1
fi

campaign_type="$1"
base="${BYREAL_CONTEST_BASE:-https://api2.byreal.io/byreal/api/dex/v2/contest}"
url="${base}/campaign/info?campaignType=${campaign_type}"

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
    # Legacy internal shape: {"code": 0, "data": {...}}
    if "code" in body:
        if body.get("code") != 0:
            print(f"api_error:{body.get('code')}", file=sys.stderr)
            sys.exit(5)
        return body.get("data")

    # Public Byreal v2 shape:
    # {"retCode": 0, "result": {"success": true, "ret_code": 0, "data": {...}}}
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

try:
    with open(sys.argv[1]) as f:
        body = json.load(f)
    data = unwrap_data(body)
    if not isinstance(data, dict):
        print("parse_error: missing data object", file=sys.stderr)
        sys.exit(5)
    json.dump(data, sys.stdout, indent=2)
    print()
except Exception as e:
    print(f"parse_error: {e}", file=sys.stderr)
    sys.exit(5)
PY
