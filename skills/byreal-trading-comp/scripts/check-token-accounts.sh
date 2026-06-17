#!/usr/bin/env bash
# Read-only SPL token account check for setup-confirm cost accounting.
#
# Usage:
#   check-token-accounts.sh --wallet W --mints M1,M2[,M3] [--rpc-url URL]
#   check-token-accounts.sh --wallet W --mint M1 --mint M2 [--rpc-url URL]
#
# Stdout (JSON):
#   {
#     "wallet": "...",
#     "rent_exempt_lamports": 2039280,
#     "accounts": [
#       {
#         "mint": "...",
#         "exists": true,
#         "pubkey": "...",
#         "lamports": 2039280,
#         "ui_amount": 0.0,
#         "ui_amount_string": "0"
#       },
#       {
#         "mint": "...",
#         "exists": false,
#         "pubkey": null,
#         "lamports": 0,
#         "ui_amount": 0.0,
#         "ui_amount_string": "0",
#         "estimated_create_rent_lamports": 2039280
#       }
#     ],
#     "missing_mints": ["..."],
#     "estimated_create_rent_lamports_total": 2039280
#   }

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

wallet=""
rpc_url="${SOLANA_RPC_URL:-https://api.mainnet-beta.solana.com}"
token_2022_account_size="512"
mints=()

usage() {
  echo "usage: $(basename "$0") --wallet W (--mints M1,M2 | --mint M1 [--mint M2...]) [--rpc-url URL] [--token-2022-account-size 512]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet)  wallet="$2"; shift 2 ;;
    --rpc-url) rpc_url="$2"; shift 2 ;;
    --token-2022-account-size) token_2022_account_size="$2"; shift 2 ;;
    --mints)
      IFS=',' read -ra split_mints <<< "$2"
      for mint in "${split_mints[@]}"; do
        mint="$(echo "$mint" | xargs)"
        [[ -n "$mint" ]] && mints+=("$mint")
      done
      shift 2
      ;;
    --mint)    mints+=("$2"); shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$wallet" || ${#mints[@]} -eq 0 ]] && usage

export _WALLET="$wallet"
export _RPC_URL="$rpc_url"
export _TOKEN_2022_ACCOUNT_SIZE="$token_2022_account_size"
export _MINTS_JSON
_MINTS_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${mints[@]}")

python3 <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

NATIVE_SOL_MINT = "So11111111111111111111111111111111111111112"
TOKEN_2022_PROGRAM = "TokenzQdBNbLqP5VEhDKMBSUjoDgduh9mzJcYicJLdK"
CLASSIC_TOKEN_ACCOUNT_SIZE = 165

wallet = os.environ["_WALLET"]
rpc_url = os.environ["_RPC_URL"]
mints = json.loads(os.environ["_MINTS_JSON"])
try:
    token_2022_account_size = int(os.environ["_TOKEN_2022_ACCOUNT_SIZE"])
    if token_2022_account_size < CLASSIC_TOKEN_ACCOUNT_SIZE:
        raise ValueError
except Exception:
    print("parse_error: --token-2022-account-size must be an integer >= 165", file=sys.stderr)
    sys.exit(5)


def rpc(method, params):
    payload = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params,
    }).encode()
    req = urllib.request.Request(
        rpc_url,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode())
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"network_failure:{e}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"parse_error:{e}", file=sys.stderr)
        sys.exit(5)
    if "error" in data:
        print(f"rpc_error:{data['error']}", file=sys.stderr)
        sys.exit(3)
    return data.get("result")


rent_by_size = {}


def rent_for_size(size):
    if size not in rent_by_size:
        rent_by_size[size] = rpc("getMinimumBalanceForRentExemption", [size])
    return rent_by_size[size]


def rent_profile_for_mint(mint):
    result = rpc("getAccountInfo", [
        mint,
        {"encoding": "jsonParsed"},
    ])
    value = result.get("value") if isinstance(result, dict) else None
    owner = value.get("owner") if isinstance(value, dict) else None
    if owner == TOKEN_2022_PROGRAM:
        return {
            "size": token_2022_account_size,
            "rent": rent_for_size(token_2022_account_size),
            "basis": "token_2022_conservative",
            "mint_program": owner,
            "warning": None,
        }
    if owner:
        return {
            "size": CLASSIC_TOKEN_ACCOUNT_SIZE,
            "rent": rent_for_size(CLASSIC_TOKEN_ACCOUNT_SIZE),
            "basis": "classic_spl",
            "mint_program": owner,
            "warning": None,
        }
    return {
        "size": token_2022_account_size,
        "rent": rent_for_size(token_2022_account_size),
        "basis": "unknown_mint_owner_conservative",
        "mint_program": None,
        "warning": "mint owner unavailable; used conservative Token-2022 rent estimate",
    }


classic_rent = rent_for_size(CLASSIC_TOKEN_ACCOUNT_SIZE)
accounts = []
missing = []
estimated_total = 0
seen = set()

for mint in mints:
    if mint in seen:
        continue
    seen.add(mint)

    if mint == NATIVE_SOL_MINT:
        accounts.append({
            "mint": mint,
            "exists": True,
            "native_sol": True,
            "pubkey": None,
            "lamports": 0,
            "ui_amount": None,
            "ui_amount_string": None,
            "estimated_create_rent_lamports": 0,
        })
        continue

    result = rpc("getTokenAccountsByOwner", [
        wallet,
        {"mint": mint},
        {"encoding": "jsonParsed"},
    ])
    values = result.get("value") or []

    if not values:
        rent_profile = rent_profile_for_mint(mint)
        estimated_total += rent_profile["rent"]
        missing.append(mint)
        entry = {
            "mint": mint,
            "exists": False,
            "native_sol": False,
            "pubkey": None,
            "lamports": 0,
            "ui_amount": 0.0,
            "ui_amount_string": "0",
            "estimated_create_account_size": rent_profile["size"],
            "estimated_create_rent_lamports": rent_profile["rent"],
            "rent_estimate_basis": rent_profile["basis"],
            "mint_program": rent_profile["mint_program"],
        }
        if rent_profile["warning"]:
            entry["rent_estimate_warning"] = rent_profile["warning"]
        accounts.append(entry)
        continue

    # Prefer the largest balance if multiple token accounts exist.
    parsed = []
    for item in values:
        info = item["account"]["data"]["parsed"]["info"]
        token_amount = info["tokenAmount"]
        parsed.append((float(token_amount.get("uiAmount") or 0), item, token_amount))
    _, item, token_amount = max(parsed, key=lambda x: x[0])
    accounts.append({
        "mint": mint,
        "exists": True,
        "native_sol": False,
        "pubkey": item["pubkey"],
        "lamports": int(item["account"].get("lamports") or 0),
        "ui_amount": token_amount.get("uiAmount"),
        "ui_amount_string": token_amount.get("uiAmountString"),
        "estimated_create_rent_lamports": 0,
    })

out = {
    "wallet": wallet,
    "rent_exempt_lamports": classic_rent,
    "rent_exempt_lamports_by_size": {str(k): v for k, v in sorted(rent_by_size.items())},
    "accounts": accounts,
    "missing_mints": missing,
    "estimated_create_rent_lamports_total": estimated_total,
}
json.dump(out, sys.stdout, indent=2)
print()
PY
