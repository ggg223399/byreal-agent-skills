#!/usr/bin/env bash
# Validate local campaign config JSON files. Also doubles as the path resolver.
#
# Usage:
#   validate-campaign-config.sh [--all]
#   validate-campaign-config.sh <campaign_type_or_json_path>
#   validate-campaign-config.sh --resolve-path <campaign_type_or_json_path>
# Env: BYREAL_CAMPAIGN_CONFIG_DIR optional directory override
#
# Stdout:
#   default       -> compact JSON summary(ies) for valid configs
#   --resolve-path -> absolute config path only
# Stderr: config_missing:<path> | config_dir_missing:<path> | config_invalid:<path>:<msg>
# Exit:   0 = OK, 1 = bad usage, 6 = any config missing/invalid

set -euo pipefail

USAGE="usage: $(basename "$0") [--all | --resolve-path <target> | <campaign_type_or_json_path>]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

mode="all"
target=""

case "${1:-}" in
  "")
    mode="all"
    ;;
  --all)
    mode="all"
    if [[ $# -ne 1 ]]; then
      echo "$USAGE" >&2
      exit 1
    fi
    ;;
  --resolve-path)
    if [[ $# -ne 2 || -z "${2:-}" ]]; then
      echo "$USAGE" >&2
      exit 1
    fi
    mode="resolve"
    target="$2"
    ;;
  -*)
    echo "$USAGE" >&2
    exit 1
    ;;
  *)
    mode="one"
    target="$1"
    if [[ $# -ne 1 ]]; then
      echo "$USAGE" >&2
      exit 1
    fi
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export _VALIDATE_MODE="$mode"
export _CAMPAIGN_TARGET="$target"

PYTHONPATH="${script_dir}/lib${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import json
import os
import sys

from campaign_config import (
    ConfigError,
    find_config,
    list_config_paths,
    load_json,
    summarize_config,
    validate_config,
)

mode = os.environ["_VALIDATE_MODE"]

if mode == "resolve":
    try:
        path, _config = find_config(os.environ["_CAMPAIGN_TARGET"])
        print(path)
    except ConfigError as e:
        msg = str(e)
        if msg.startswith(("campaign_", "config_")):
            print(msg, file=sys.stderr)
        else:
            print(f"config_invalid:{msg}", file=sys.stderr)
        sys.exit(6)
    except Exception as e:
        print(f"config_invalid:{e}", file=sys.stderr)
        sys.exit(6)
    sys.exit(0)

if mode == "one":
    try:
        path, config = find_config(os.environ["_CAMPAIGN_TARGET"])
        json.dump(summarize_config(path, config), sys.stdout, indent=2)
        print()
    except ConfigError as e:
        msg = str(e)
        if msg.startswith(("campaign_", "config_")):
            print(msg, file=sys.stderr)
        else:
            print(f"config_invalid:{msg}", file=sys.stderr)
        sys.exit(6)
    except Exception as e:
        print(f"config_invalid:{e}", file=sys.stderr)
        sys.exit(6)
    sys.exit(0)

try:
    paths = list_config_paths()
except ConfigError as e:
    print(str(e), file=sys.stderr)
    sys.exit(6)

out = []
failed = False
for path in paths:
    try:
        config = load_json(path)
        validate_config(config, path)
        out.append(summarize_config(path, config))
    except Exception as e:
        failed = True
        print(f"config_invalid:{path}:{e}", file=sys.stderr)

json.dump(out, sys.stdout, indent=2)
print()
sys.exit(6 if failed else 0)
PY
