#!/usr/bin/env bash
# Read the current UI balance for one wallet/mint from byreal-cli.
#
# Usage:
#   read-live-token-balance.sh --wallet W --mint M [--symbol SYMBOL] [--raw]
#
# Stdout JSON:
#   {
#     "wallet": "...",
#     "mint": "...",
#     "exists": true,
#     "matched_tokens": 1,
#     "live_balance_ui": "139.485841"
#   }
#
# With --raw, stdout is only the live_balance_ui string.

set -euo pipefail

wallet=""
mint=""
symbol=""
raw="0"

usage() {
  echo "usage: $(basename "$0") --wallet W --mint M [--symbol SYMBOL] [--raw]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wallet) wallet="$2"; shift 2 ;;
    --mint)   mint="$2"; shift 2 ;;
    --symbol) symbol="$2"; shift 2 ;;
    --raw)    raw="1"; shift ;;
    *) usage ;;
  esac
done

[[ -z "$wallet" || -z "$mint" ]] && usage

if ! command -v byreal-cli >/dev/null 2>&1; then
  echo "missing_command:byreal-cli" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "missing_command:python3" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

read_configured_wallet() {
  byreal-cli wallet address 2>/dev/null \
    | python3 -c 'import re,sys; raw=sys.stdin.read(); matches=re.findall(r"\b[1-9A-HJ-NP-Za-km-z]{32,44}\b", raw); print(matches[0] if matches else "")'
}

set +e
byreal-cli wallet balance --wallet-address "$wallet" -o json > "$tmp" 2>&1
exit_code=$?
set -e

if [[ $exit_code -ne 0 ]] && grep -qi -- "--wallet-address" "$tmp"; then
  configured_wallet="$(read_configured_wallet)"
  if [[ "$configured_wallet" != "$wallet" ]]; then
    echo "wallet_selector_unsupported: byreal-cli does not support --wallet-address; configured_wallet=${configured_wallet:-unknown} requested_wallet=$wallet" >&2
    cat "$tmp" >&2
    exit 2
  fi

  set +e
  byreal-cli wallet balance -o json > "$tmp" 2>&1
  exit_code=$?
  set -e
fi

if [[ $exit_code -ne 0 ]]; then
  echo "balance_read_failed: byreal-cli exited $exit_code" >&2
  cat "$tmp" >&2
  exit 2
fi

export _BALANCE_RESP="$tmp"
export _WALLET="$wallet"
export _MINT="$mint"
export _SYMBOL="$symbol"
export _RAW="$raw"

PYTHONPATH="${script_dir}/lib${PYTHONPATH:+:$PYTHONPATH}" python3 <<'PY'
import json
import os
import sys
from decimal import Decimal, InvalidOperation

from byreal_cli_json import extract_success_object_from_file, iter_json_objects

NATIVE_SOL_MINT = "So11111111111111111111111111111111111111112"

path = os.environ["_BALANCE_RESP"]
wallet = os.environ["_WALLET"]
mint = os.environ["_MINT"]
symbol_filter = os.environ.get("_SYMBOL") or ""
raw_only = os.environ["_RAW"] == "1"


def first_json_object_from_file(filename):
    with open(filename) as f:
        raw = f.read()
    for candidate in iter_json_objects(raw):
        try:
            obj = json.loads(candidate)
        except Exception:
            continue
        if isinstance(obj, dict):
            return obj
    return None


parsed = extract_success_object_from_file(path)
if parsed is None:
    parsed = first_json_object_from_file(path)
if parsed is None:
    print("parse_error: wallet balance output did not contain JSON", file=sys.stderr)
    sys.exit(5)
if parsed.get("success") is False:
    err = parsed.get("error", {}).get("message", "unknown")
    print(f"balance_read_failed: {err}", file=sys.stderr)
    sys.exit(2)

data = parsed.get("data") if isinstance(parsed.get("data"), dict) else parsed
balance = data.get("balance") if isinstance(data.get("balance"), dict) else data
tokens = balance.get("tokens") if isinstance(balance.get("tokens"), list) else []


def dec(raw):
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, ValueError):
        return None
    if not value.is_finite() or value < 0:
        return None
    return value


def dec_plain(value):
    text = format(value.normalize(), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"


def field(obj, names):
    for name in names:
        if isinstance(obj, dict) and name in obj and obj[name] is not None:
            return obj[name]
    return None


def token_mints(token):
    values = []
    for name in ("mintAddress", "mint_address", "mint", "address", "tokenMint", "token_mint"):
        value = field(token, (name,))
        if value:
            values.append(str(value))
    return values


def token_symbol(token):
    value = field(token, ("symbol", "tokenSymbol", "token_symbol"))
    return str(value) if value else ""


def token_amount(token):
    value = field(token, (
        "amount_ui",
        "amountUi",
        "ui_amount",
        "uiAmount",
        "uiAmountString",
        "amount",
        "balance",
    ))
    return dec(value) if value is not None else None


matches = []
for token in tokens:
    if not isinstance(token, dict):
        continue
    mint_match = mint in token_mints(token)
    symbol_match = bool(symbol_filter) and token_symbol(token).lower() == symbol_filter.lower()
    if not mint_match and not symbol_match:
        continue
    amount = token_amount(token)
    if amount is None:
        continue
    matches.append({
        "symbol": token_symbol(token) or None,
        "mints": token_mints(token),
        "amount": amount,
    })

amount = sum((m["amount"] for m in matches), Decimal("0"))

# Some wallet balance implementations expose native SOL outside tokens[].
if not matches and mint == NATIVE_SOL_MINT:
    native = field(balance, (
        "sol",
        "SOL",
        "sol_balance",
        "solBalance",
        "native_sol",
        "nativeSol",
        "nativeBalance",
    ))
    if isinstance(native, dict):
        native = field(native, (
            "amount_ui",
            "amount_sol",
            "amountSol",
            "uiAmount",
            "uiAmountString",
            "amount",
            "balance",
        ))
    native_amount = dec(native) if native is not None else None
    if native_amount is not None:
        amount = native_amount
        matches.append({"symbol": "SOL", "mints": [NATIVE_SOL_MINT], "amount": native_amount})

out = {
    "wallet": wallet,
    "mint": mint,
    "symbol_filter": symbol_filter or None,
    "exists": bool(matches),
    "matched_tokens": len(matches),
    "live_balance_ui": dec_plain(amount),
}
if matches:
    out["matched_symbols"] = sorted({m["symbol"] for m in matches if m["symbol"]})

if raw_only:
    print(out["live_balance_ui"])
else:
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    print()
PY
