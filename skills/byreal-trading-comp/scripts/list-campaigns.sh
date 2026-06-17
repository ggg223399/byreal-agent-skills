#!/usr/bin/env bash
# List the trading-competition campaigns this skill knows how to run.
#
# Two sources of truth: the local JSON config dir (which campaigns the skill has
# scoring + pool rules for) and the contest API (which campaigns the org has
# announced and what their windows are). A campaign is usable only when both
# sides agree, so the script can fold them together for the caller.
#
# Usage:
#   list-campaigns.sh                # local only — fast, never hits the network
#   list-campaigns.sh --with-status  # also resolves each via fetch-campaign.sh
#                                    # and labels status as upcoming|active|ended|unknown
#
# Env: BYREAL_CAMPAIGN_CONFIG_DIR optional directory override for <type>.json lookup
#
# Stdout (JSON array, one entry per <type>.json under the config dir):
#   [
#     { "campaign_type": "wlfi_season_1",
#       "eligible_pool_names": ["USD1-USDC","WLFI-USDC"],
#       "notes": "..."
#       # with --with-status, plus:
#       "name": "...", "startTime": 1717200000000, "endTime": 1717804800000,
#       "status": "active"
#     }
#   ]
#
# Stderr:
#   "config_invalid:<file>:<msg>"          per malformed config (entry skipped)
#   "campaign_lookup_failed:<type>:<msg>"  with --with-status, per API miss
#                                          (entry still listed with status=unknown)
#
# Exit:
#   0 = directory exists, JSON written (array may be empty)
#   1 = bad usage
#   6 = config directory missing

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

with_status=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-status) with_status=1; shift ;;
    *) echo "usage: $(basename "$0") [--with-status]" >&2; exit 1 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
raw_config_dir="${BYREAL_CAMPAIGN_CONFIG_DIR:-${script_dir}/../config/campaigns}"
raw_config_dir="${raw_config_dir/#\~/$HOME}"

if [[ ! -d "$raw_config_dir" ]]; then
  echo "config_dir_missing:${raw_config_dir}" >&2
  exit 6
fi
config_dir="$(cd "$raw_config_dir" && pwd)"
status_file=$(mktemp)
status_dir=$(mktemp -d)
trap 'find "$status_dir" -type f -delete 2>/dev/null || true; rmdir "$status_dir" 2>/dev/null || true; rm -f "$status_file"' EXIT

# Pre-resolve statuses (if requested) so the python aggregator stays pure.
# fetch-campaign.sh is the authoritative window source — reuse it rather than
# re-implementing the API call.
status_lines=()
if [[ $with_status -eq 1 ]]; then
  shopt -s nullglob
  for f in "$config_dir"/*.json; do
    ct=$(basename "$f" .json)
    set +e
    api_json=$("$script_dir/fetch-campaign.sh" "$ct" 2>/dev/null)
    api_exit=$?
    set -e
    if [[ $api_exit -ne 0 ]]; then
      echo "campaign_lookup_failed:${ct}:exit_${api_exit}" >&2
      status_lines+=("${ct}|UNKNOWN|")
    else
      api_path="${status_dir}/${ct}.json"
      printf '%s\n' "$api_json" > "$api_path"
      status_lines+=("${ct}|OK|${api_path}")
    fi
  done
  shopt -u nullglob
fi

export _CONFIG_DIR="$config_dir"
export _WITH_STATUS="$with_status"
# Pass per-campaign API JSON through a tmpfile to avoid arg-length issues if
# many campaigns are registered. Format: one record per line, type|state|path.
if [[ $with_status -eq 1 ]]; then
  for line in "${status_lines[@]}"; do
    printf '%s\n' "$line" >> "$status_file"
  done
fi
export _STATUS_FILE="$status_file"

PYTHONPATH="${script_dir}/lib${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import json, os, sys, time, glob
from campaign_config import ConfigError, load_json, validate_config

config_dir = os.environ["_CONFIG_DIR"]
with_status = os.environ["_WITH_STATUS"] == "1"

status_map = {}
if with_status:
    with open(os.environ["_STATUS_FILE"]) as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            ct, state, path = raw.split("|", 2)
            status_map[ct] = (state, path)

now_ms = int(time.time() * 1000)

def classify(start_ms, end_ms):
    if start_ms is None or end_ms is None:
        return "unknown"
    if now_ms < start_ms:
        return "upcoming"
    if now_ms > end_ms:
        return "ended"
    return "active"

out = []
for path in sorted(glob.glob(os.path.join(config_dir, "*.json"))):
    ct = os.path.basename(path)[:-5]
    try:
        cfg = load_json(path)
        validate_config(cfg, path)
        entry = {
            "campaign_type": ct,
            "eligible_pool_names": [p["name"] for p in cfg.get("eligible_pools", [])],
            "notes": cfg.get("notes"),
        }
        if "display" in cfg:
            entry["display"] = cfg["display"]
    except (ConfigError, Exception) as e:
        print(f"config_invalid:{path}:{e}", file=sys.stderr)
        continue

    if with_status:
        state, path = status_map.get(ct, ("UNKNOWN", ""))
        if state == "OK" and path:
            try:
                with open(path) as f:
                    api = json.load(f)
                entry["name"] = api.get("name")
                entry["startTime"] = api.get("startTime")
                entry["endTime"] = api.get("endTime")
                entry["status"] = classify(entry["startTime"], entry["endTime"])
            except Exception as e:
                print(f"campaign_lookup_failed:{ct}:parse_{e}", file=sys.stderr)
                entry["status"] = "unknown"
        else:
            entry["status"] = "unknown"

    out.append(entry)

json.dump(out, sys.stdout, indent=2)
print()
PY
