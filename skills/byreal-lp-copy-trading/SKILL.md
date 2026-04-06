---
name: byreal-lp-copy-trading
version: 0.1.0
description: "Copy strong CLMM positions on Byreal, manage lifecycle, auto-compound, stop-loss."
---

# Strategy: LP Copy Trading

> Copy strong CLMM positions on Byreal, manage the copied position lifecycle, auto-compound fees, and stop-loss on drawdown.
>
> **Depends on**: AGENTS.md §Transaction Safety, §Risk Limits (slippage, gas reserve), §Error Handling, §Audit Trail, §User Permission Model. This Skill only defines strategy-specific logic.

## Overview

| Attribute | Value |
|-----------|-------|
| Category | LP — Copy Trading |
| Risk | Active (A) — inherits the source wallet's pool and range choices; adds execution lag and adverse selection risk |
| Complexity | *** Multi-step automated |
| Market | Byreal CLMM pools — pool selection delegated to the followed source wallet, subject to pool safety checks |
| Cycle | Continuous (H) |
| Min Capital | 100 USDC per position; 300 USDC recommended for multi-position or lower-latency tracking setups. **Enforced at startup** — see Startup Step 0. |

## Published CLI Compatibility

Validated against published `@byreal-io/byreal-cli-realclaw` `0.3.3` on 2026-04-01.

- **Directly supported by the published CLI**: pool discovery, pool analysis, top positions within a pool, one-shot position copy, lifecycle management of **my** copied position (`analyze`, `increase`, `claim`, `close`) by **NFT mint**, and wallet-level polling of **other users' positions** via `positions list --user <wallet>`.
- **Still not exposed as first-class commands**: dedicated `farmers top`, source-wallet event subscriptions, or source-wallet-specific real-time streams. Discovery remains pool-first; source-wallet tracking is implemented by polling wallet positions.
- **Important validation**: `positions analyze <nft-mint>` is still safest to treat as a wallet-scoped deep analysis command for positions you already control. For monitoring other users, use `positions list --user <wallet>` and diff snapshots instead of assuming arbitrary external NFT analysis works.
- **Implication**: `position`, `pair`, and `address` modes are now implementable with published `byreal-cli` alone via wallet polling. Real-time subscriptions and zero-latency eventing still require an optional external watcher / indexer.
- **Execution mode split**:
  - Main CLI `0.2.9`: local wallet model, `wallet address` exists, write commands use `--confirm` or `--unsigned-tx`.
  - RealClaw CLI `0.3.3`: unsigned-tx model, top-level `--wallet-address` is required for write commands, and write subcommands do **not** expose `--confirm`.

## Supported Pools (MVP)

V1 does NOT maintain a static pool allowlist for copy trading — pool selection is delegated to the followed source wallet. However, every pool must pass the safety gate before capital is deployed:

| Check | Threshold | Action |
|-------|-----------|--------|
| Pool TVL | >= 50,000 USDC | Below → block copy + warn user |
| 24h Volume | >= 5,000 USDC | Below → warn user, allow with confirmation |
| Pool age | >= 48h | Below → block copy + warn user |
| Contract audit | Byreal CLMM only | Non-Byreal pools → block |

Do not auto-copy into pools that fail the safety gate. If the source wallet opens a position in a pool that fails, log the skip and alert the user.

## Follow Modes

| Mode | Entry Path | Tracks | Scope |
|------|-----------|--------|-------|
| `position` | User finds a top position → copies it | That single source position PDA / source wallet / my copied NFT | **CLI-native.** Copy + copied-position monitoring + original-position lifecycle monitoring are supported via `positions list --user <source_wallet>` plus saved source identifiers. |
| `pair` | User copies a position → then tracks the same pair on the source wallet | Source wallet, filtered to `target_pair` only | **CLI-native polling.** Implement by polling `positions list --user <source_wallet>` and filtering to the tracked pair. Optional external watcher only improves latency. |
| `address` | User follows a source wallet across all pairs | Source wallet, all pairs | **CLI-native polling.** Implement by polling `positions list --user <source_wallet>` and diffing snapshots over time. |

## Requires

```yaml
feeds:
  - pools-list             # list candidate pools by TVL / volume / APR
  - pool-info              # detailed pool metadata (`pools info`) for age / token / static fields
  - top-positions          # top copyable positions in a specific pool (`positions top-positions`)
  - source-wallet-positions # source wallet polling via `positions list --user <wallet>`
  - position-detail        # unclaimed fees, IL%, PnL, range status for my positions
  - pool-state             # current price, metrics.tvl, metrics.volume24h, feeApr24h, risk summary
  - wallet-balance         # available SOL + SPL balances

execution:
  - copy-position          # copy an existing position PDA with the same range (`positions copy`)
  - open-position          # open CLMM position with specified tick range and amount_usd (fallback / manual mode)
  - close-position         # close position by NFT mint (collect fees + remove liquidity)
  - collect-fees           # harvest accrued fees
  - increase-position      # reinvest harvested fees into existing position (`positions increase --nft-mint`)
  - swap                   # rebalance token ratio for position entry. Current CLI uses `swap execute --input-mint/--output-mint --amount --slippage <bps>`. On failure: retry once with higher bps, then try alternative intermediate token. If all fail, abort and alert user.

risk:
  - pool-safety-gate       # TVL, volume, age, contract checks before copying
  - stop-loss-check        # compare current position value vs entry; exit if below threshold
  - lag-awareness          # log time delta between source-wallet action and our mirror action
  # balance-check, gas-check, max-budget-guard inherited from AGENTS.md §Strategy Watchdog

# Published CLI note:
#   There is no dedicated source-wallet command family in public byreal-cli.
#   Source-wallet tracking is done by polling `positions list --user <wallet>`.
#   Copy targets are still discovered from `positions top-positions --pool <pool>`.
#
# Wallet access model:
#   Copier wallet — READ-WRITE (copy/open/close/claim/swap via byreal-cli)
#   In RealClaw production each instance owns one wallet; no switching needed.
```

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `follow_mode` | enum | `position` | `position` / `pair` / `address` | See Follow Modes above. |
| `target_pair` | string | — | required only in `pair` mode | Auto-set from the initial copied position. |
| `amount_usd` | number | `100` | `100–5000` | USDC to deploy per mirrored position. Subject to Position Budget Rules. |
| `max_total_usd` | number | `1000` | `>= amount_usd` | Hard cap on total deployed capital. Cannot exceed AGENTS.md §Risk Limits budget cap. |
| `compound_threshold` | number | `5` | `0.50–100` | Minimum unclaimed fees (USDC) to trigger auto-compound. |
| `compound_interval` | duration | `12h` | `1h–7d` | How often to scan for compounding eligibility. |
| `monitor_interval` | duration | `10m` | `10m–1h` | Monitoring loop frequency. Minimum 10m due to Byreal API cache (5-10m). |
| `stop_loss_enabled` | bool | `false` | — | Auto-exit on stop-loss only if explicitly approved at strategy start. |
| `stop_loss_pct` | number | `15` | `1–50` | Base stop-loss %. Dynamically adjusted by pool category (see Step 4). |
| `max_positions` | integer | `10` | `1–50` | Maximum simultaneously open mirrored positions. |
| `max_source_wallets` | integer | `1` | `1–10` | V1 tracks one source wallet per strategy instance. Multi-wallet following should run multiple strategy instances; `max_source_wallets` is reserved for future orchestration. |
| `notify_on_source_close` | bool | `false` | — | Derived source-close notification flag. Automatically forced by `source_close_action`: `notify` and `close_copy` force `true`; `none` forces `false`. |
| `source_close_action` | enum | `none` | `none` / `notify` / `close_copy` | What to do when the original source position closes. Must remain `none` until the user explicitly selects a source-close policy at strategy start. |
| `auto_compound` | bool | `false` | — | Enable automatic fee reinvestment only if explicitly approved at strategy start. |
| `auto_follow_new` | bool | `false` | — | Auto-copy the source wallet's new positions (pair-filtered in `pair` mode) only if explicitly approved. |
| `auto_follow_close` | bool | `false` | — | Auto-close when the source wallet closes only if explicitly approved. |
| `auto_rebalance` | bool | `false` | — | Auto-mirror the source wallet's rebalancing only if explicitly approved. Only in `pair` and `address` modes. |
| `slippage_tolerance` | number | `1.0` | `0.1–3.0` | Max slippage percent. AGENTS.md §Risk Limits rules auto-tighten for stablecoin pools. |

## Scheduler And Runtime State

This strategy is driven by one isolated scheduler job per strategy instance.

- Register one `openclaw cron` job at strategy start, named `byreal-lp-copy-trading-<strategy_id>`.
- Run it every `monitor_interval`.
- The cron executor must read this skill, load the strategy runtime state, run one monitoring cycle, and then persist updated state.

Example registration:

```bash
# ⚠ NEVER add --announce or --to — see AGENTS.md §Notification Routing
openclaw cron add \
  --name byreal-lp-copy-trading-<strategy_id> \
  --every <monitor_interval> \
  --session isolated \
  --timeout-seconds 600 \
  --message "LP Copy Trading executor. Read the skill file at ~/.openclaw/workspace/skills/byreal-lp-copy-trading/SKILL.md, load this strategy's runtime state, run one monitoring cycle, and persist state and watchdog fields. Do not send messages to user."
```

Persist these watchdog fields in the strategy runtime state so AGENTS.md §Strategy Watchdog can monitor health:

- `last_heartbeat`
- `current_step`
- `last_success_at`
- `retry_count`

Per-cycle watchdog performance snapshot should also be persisted or emitted with at least:

- `strategy_id`
- `strategy_name: "LP Copy Trading"`
- `status`
- `budget_usd`
- `current_value_usd`
- `net_pnl_usd`
- `net_pnl_percent`
- `total_fees_earned_usd`
- `total_costs_usd`
- `days_active`
- `last_report_at`
- `alerts`

Useful optional fields for this strategy:

- `effective_apy`
- `il_percent`
- `compound_count`
- `copy_leader`

Recommended recurring state fields:

- `last_monitor_at`
- `last_compound_at`
- `last_snapshot_at`
- `source_wallet_address`
- `alerts`

## Position Budget Rules

Capital allocation to prevent over-deployment. Tested: without these rules, a single initial position can consume ~93% of funds, leaving nothing for subsequent opens.

```
# Gas reserve per AGENTS.md §Risk Limits (≥0.01 SOL, auto-top-up within $10/24h cap)
# Keep a single global reserve for future compounding instead of reserving per position.
compound_reserve = auto_compound ? min(max_total_usd * 0.05, 50 USDC) : 0
remaining_budget = max(0, max_total_usd - sum(deployed positions value) - compound_reserve)

IF follow_mode == "position" (single position):
  max_per_position = min(amount_usd, available_balance * 0.90)
  buffer: 10% held for rebalance swap costs

IF follow_mode == "pair" OR "address" (multi-position possible):
  first_position:       max 60% of remaining_budget
  subsequent_positions: each gets min(amount_usd, remaining_budget * 0.40 / expected_count)

Before EVERY open:
  actual_available = min(check_balance() - gas_reserve, remaining_budget)
  IF actual_available < 2 USDC: SKIP + LOG "BUDGET_EXHAUSTED"
  open_amount = min(target_amount, actual_available * 0.95)
  IF opening a brand-new mirrored position AND open_amount < 100 USDC:
    SKIP + LOG "MIN_POSITION_NOT_MET"
```

## Required Preapproval At Strategy Start

Per AGENTS.md §User Permission Model, starting a strategy captures an active permission. This strategy needs these **specific** decisions:

> 1. **Follow behavior**: Auto-copy new positions? [Yes / No, notify me]
> 2. **Close behavior**: Auto-close when the source wallet closes? [Yes / No, keep open]
> 3. **Rebalance behavior**: Auto-rebalance when the source wallet rebalances? [Yes / No, notify only]
> 4. **Compound behavior**: Auto-compound fees? [Yes / No]
> 5. **Stop-loss**: Auto-exit at {stop_loss_pct}%? [Yes / No, alert only]
> 6. **Source-close behavior**: If the original source position closes, [Notify me / Auto-close my copy / No action]
> 7. **Budget**: Confirm max {max_total_usd} USDC

Map approvals directly to runtime flags: `auto_follow_new`, `auto_follow_close`, `auto_rebalance`, `auto_compound`, `stop_loss_enabled`, `notify_on_source_close`, and `source_close_action`.

Default all of these flags to `false` until the user explicitly opts in. Budget cannot be increased without re-confirmation.
In published CLI `position` mode, copied-position monitoring and source-close detection are both CLI-native when the source wallet is known and polled via `positions list --user`. `auto_compound`, `stop_loss_enabled`, `notify_on_source_close`, and `source_close_action` are actionable in that setup.
Normalize source-close config before start:
- default `source_close_action = "none"`
- IF user explicitly selects `source_close_action == "notify"` → force `notify_on_source_close = true`
- IF user explicitly selects `source_close_action == "close_copy"` → force `notify_on_source_close = true` and send an informational TG message after auto-close
- IF user explicitly selects `source_close_action == "none"` → force `notify_on_source_close = false`

## Decision Logic

```
# Write-command note:
# - The primary runtime below assumes RealClaw CLI `0.3.3`.
# - Use top-level `--wallet-address <address>` for write commands and omit `--confirm`.
# - Main CLI `0.2.9` compatibility examples remain in the appendix only.
#
## Startup

0. GAS CHECK + CAPITAL GATE (hard block):
   IF wallet SOL < 0.01 SOL: BLOCK startup + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"
   byreal-cli wallet balance -o json → available_usdc
   IF available_usdc < 100 USDC (min capital per position):
     BLOCK startup. ALERT user: "Insufficient capital. Need ≥100 USDC, have {available_usdc}. Deposit and retry."
     EXIT.
   IF follow_mode != "position" AND available_usdc < 300 USDC:
     WARN user: "Multi-position tracking recommended ≥300 USDC. Proceed with {available_usdc}? [Yes / Deposit more]"

1. VALIDATE parameters
2. VALIDATE strategy permission captured (see Preapproval)

3. FIND TARGETS:
   # Path A: pool-first discovery → position mode (published CLI)
   byreal-cli pools list --sort-field volumeUsd24h --sort-type desc --page-size 10 -o json
   → choose candidate pool(s)
   byreal-cli positions top-positions --pool <pool_address> --sort-field earned --status 0 -o json
   → user selects source position PDA
   Persist source identifiers from the selected row:
     source_position_address (required)
     source_nft_mint        (if exposed by top-positions output)
   Resolve `source_wallet_address`:
     IF the selected row exposes the source wallet / owner address:
       persist it
     ELSE:
       ask the user to provide or confirm the source wallet address
       IF source_wallet_address remains unknown:
         BLOCK startup. ALERT user: "Cannot monitor the original position without the source wallet address."
   IF position mode: track that source position on source_wallet_address plus my copied NFT
   IF pair mode:
     derive target_pair from the selected source position
     byreal-cli positions list --user <source_wallet_address> -o json → source_wallet_positions
     initial_pair_candidates = filter_to_pair(source_wallet_positions, target_pair)
     IF initial_pair_candidates is empty:
       BLOCK startup. ALERT user: "No readable source-wallet positions found on {target_pair}. Verify the wallet and retry."

   # Path B: address mode
   User provides or confirms source_wallet_address
   byreal-cli positions list --user <source_wallet_address> -o json → source_wallet_positions
   IF source_wallet_positions is empty AND no user-selected source position is provided:
     BLOCK startup. ALERT user: "Unable to read source wallet positions. Verify the wallet address and retry."
   IF pair mode:
     require either:
       a user-selected source position from `source_wallet_positions`, or
       a user-specified `target_pair`
     IF neither is available:
       BLOCK startup. ALERT user: "Pair mode requires a source position or target pair."
     IF target_pair is still unset:
       derive target_pair from the selected source position

4. INSPECT TARGET POSITION:
   Build candidate metadata from the active discovery path:
     pool-first / top-positions path → use the selected `positions top-positions` row
     wallet-first path               → use the shortlisted `positions list --user` rows
   For each candidate, ensure source metadata includes:
     source_position_address
     source_wallet_address
     pair
     poolAddress
     tickLower / tickUpper
   Optionally preview each candidate with:
   byreal-cli positions copy --position <candidate.source_position_address> --amount-usd <amount_usd> --dry-run -o json

4b. RANK COPY CANDIDATES:
   HARD FILTERS:
     status == open
     inRange == true
     liquidityUsd >= 1
     source_position_address is present / copyable
     pool passes safety gate
     position age >= 10 minutes if age is available
   SOFT RANKING (highest first):
     1. higher earned fees / realized PnL / APR
     2. higher copies count / bonus score
     3. newer or longer-surviving positions if age is available
   Each shortlisted candidate must carry:
     source_position_address
     source_wallet_address
     pair
     poolAddress
     tickLower / tickUpper
   If a candidate does not expose a copyable `source_position_address`, SKIP + LOG "SKIP_NO_SOURCE_POSITION_PDA"
   LIMIT initial shortlist to:
     position mode: exactly 1 user-selected position
     pair mode: source wallet positions filtered to target_pair
     address mode: source wallet positions subject to budget / max_positions
   IF ranked shortlist is empty after hard filters:
     BLOCK startup. ALERT user: "No copyable source positions passed the safety and data checks."

5. POOL SAFETY GATE (for each position to copy):
   byreal-cli pools info <pool> -o json    → pool metadata / static fields
   byreal-cli pools analyze <pool> -o json → { metrics.tvl, metrics.volume24h, metrics.feeApr24h, riskFactors, rangeAnalysis }
   Derive pool age from `pools info` metadata when available.
   If required metadata for a hard gate is unavailable, FAIL CLOSED: do not auto-copy until confirmed.
   Apply thresholds from Supported Pools table

6. PRE-FLIGHT: check balance vs required amount (per Position Budget Rules)
   Enforce max_positions against current mirrored count + startup candidate count

7. EXECUTE INITIAL COPY:
   FOR each target_position in the ranked shortlist passing safety gate:
     Apply Position Budget Rules to determine open_amount
     IF open_amount < 100 USDC: SKIP + LOG "MIN_POSITION_NOT_MET"
     byreal-cli positions copy --position <target_position.source_position_address> \
       --amount-usd <open_amount> --dry-run -o json
     THEN:
     byreal-cli --wallet-address <copier_wallet> positions copy --position <target_position.source_position_address> \
       --amount-usd <open_amount> -o json
     RECORD state: {
       source_position_address: target_position.source_position_address,
       source_nft_mint?: target_position.source_nft_mint,
       source_wallet_address: target_position.source_wallet_address,
       my_nft_mint,
       pair: target_position.pair,
       pool: target_position.poolAddress,
       tick_lower: target_position.tickLower,
       tick_upper: target_position.tickUpper,
       deposited_usd: open_amount,
       opened_at,
       tx
     }

7b. VERIFY COPY (post-open sanity check):
   FOR each newly opened mirrored position record:
     byreal-cli positions analyze <record.my_nft_mint> -o json
     VERIFY: pool matches `record.pool`
     VERIFY: tick range matches stored source ticks [`record.tick_lower`, `record.tick_upper`] (exact or within 1 tick spacing)
     VERIFY: returned nftMintAddress matches stored `record.my_nft_mint`
     IF mismatch: ALERT user "Copy verification failed — pool, range, or ID mismatch. Review position {record.my_nft_mint}."

8. BUILD SNAPSHOT:
   IF position mode:
     Store source_position_address + source_nft_mint? + source_wallet_address + my_nft_mint + pool + pair
   ELSE:
     Initialize the tracked source wallet for this strategy instance with:
       last_snapshot = current source-wallet positions within this strategy's monitoring scope
                      (`target_pair`-filtered in pair mode; all source-wallet positions in address mode)
       pair_index = positions indexed by pair
       last_checked = now()
       stale_count = 0
     Initialize local_state.defer_counts = {}

9. LOG: "Copy trading active."

## Monitoring Loop

EVERY monitor_interval:

IF follow_mode == "position":
  # Poll both my wallet and the source wallet directly via byreal-cli.
  byreal-cli positions list --user <copier_wallet> -o json → wallet_positions
  active_positions = reconcile_tracked_positions(wallet_positions, local_state)
  byreal-cli positions list --user <source_wallet_address> -o json → source_wallet_positions
  source_positions = reconcile_source_positions(source_wallet_positions, local_state)
  source_status = detect_source_status(source_positions, source_position_address, source_nft_mint)
  IF source_status transitioned OPEN → CLOSED:
    local_state.source_closed_at = now()
    # Direct push — Decision-required exception (see AGENTS.md §Notification Routing)
    IF source_close_action == "notify":
      SEND Telegram notification:
        "Original source position closed. Your copied position is still open."
        Actions: [Keep monitoring] [Close my copy] [Pick a new position to copy]
      local_state.pending_user_decision = "source_closed"
    # Direct push — Decision-required exception (see AGENTS.md §Notification Routing)
    ELIF source_close_action == "close_copy":
      FOR each pos in active_positions:
        byreal-cli --wallet-address <copier_wallet> positions close --nft-mint <pos.nft_mint> -o json
      LOG "SOURCE_CLOSED_AUTO_CLOSED_COPY"
      SEND Telegram notification:
        "Original source position closed. Your copied position has been auto-closed."
      active_positions = []
      GOTO Step 6
    ELSE:
      LOG "SOURCE_CLOSED_NO_ACTION"
  # Reconciliation rules:
  # - remove tracked NFTs no longer present / no longer active
  # - keep any tracked copied NFT still active
  # - source position is considered still open if it remains present on source_wallet_address
  # - if a new copy was recorded in local_state since last cycle, add it to active_positions
  # - if old position closed and replacement copy exists, replacement becomes the monitored position
  GOTO Step 4

### Step 1 — Fetch Source Wallet State
### Steps 1-3 use CLI polling against the source wallet. Optional external watchers only improve latency.
# V1 assumption: one source wallet per strategy instance. Multi-wallet following
# should run separate strategy instances until orchestration is introduced.
# Pair/address mode still needs the copier wallet as the source of truth for
# stop-loss, compounding, budget, and max_positions checks.
byreal-cli positions list --user <copier_wallet> -o json → wallet_positions
active_positions = reconcile_tracked_positions(wallet_positions, local_state)

# Byreal position API has 5-10 min cache.
# If result is identical to last snapshot, optionally cross-check via RPC
# (getTokenAccountsByOwner for NFT mints) before skipping.
#
# liquidityUsd reliability: API may return liquidityUsd=0 for newly opened
# positions even when funds are deposited. For copied positions I already control,
# I can fallback to `byreal-cli positions analyze <nft_mint>` for actual value.
# For source-wallet monitoring, prefer the deposited_amount recorded at open time
# or confirm on the next cycle instead of assuming arbitrary external NFT analysis.

FOR each tracked_source_wallet:
  byreal-cli positions list --user <tracked_source_wallet.address> -o json → current_positions
  IF pair mode: current_positions = filter_to_pair(current_positions, target_pair)
  IF API error: log, skip. 3 consecutive failures → alert user.

  # Stale-cache detection
  IF current_positions == tracked_source_wallet.last_snapshot (exact match):
    tracked_source_wallet.stale_count += 1
    IF tracked_source_wallet.stale_count >= 3: LOG WARNING "API stale for 3+ cycles"
    CONTINUE

### Step 2 — Diff (Pair-Aware Rebalance Detection)

  rebalanced = []
  pure_closed = []
  pure_new = []
  snapshot_ids = ids(tracked_source_wallet.last_snapshot)
  current_ids  = ids(current_positions)
  raw_closed = snapshot_ids - current_ids
  raw_new    = current_ids - snapshot_ids

  # CLMM Rebalance Detection:
  # Positions are NFTs with fixed tick ranges.
  # "Rebalance" = close position A on pair X + open position B on SAME pair X.
  # Group closed and new by pair. Same-pair close+open = atomic rebalance.
  # Use a stable position key derived from `positionAddress` when present,
  # otherwise fall back to `nftMintAddress`. Use `tickLower` / `tickUpper`
  # as the source-of-truth range fields from `positions list`.

  closed_by_pair = group_by_pair(raw_closed, tracked_source_wallet.last_snapshot)
  new_by_pair    = group_by_pair(raw_new, current_positions)

  FOR each pair in (closed_by_pair.keys() | new_by_pair.keys()):
    closed_on_pair = closed_by_pair.get(pair, [])
    new_on_pair    = new_by_pair.get(pair, [])

    IF len(closed_on_pair) > 0 AND len(new_on_pair) > 0:
      matched = min(len(closed_on_pair), len(new_on_pair))
      FOR i in range(matched):
        old_pos = closed_on_pair[i]
        new_pos = new_on_pair[i]
        rebalanced.append({
          "closed_id": position_key(old_pos),
          "new_id": position_key(new_pos),
          "pair": pair,
          "old_range": [old_pos.tickLower, old_pos.tickUpper],
          "new_range": [new_pos.tickLower, new_pos.tickUpper]
        })
      pure_closed.extend(closed_on_pair[matched:])
      pure_new.extend(new_on_pair[matched:])
    ELSE:
      pure_closed.extend(closed_on_pair)
      pure_new.extend(new_on_pair)

### Step 3 — Execute Follow Actions

# Mirrored state must be indexed by the same source-position key used in diffing:
# `position_key(source_position)` = `positionAddress` when present, otherwise `nftMintAddress`.
# `find_my_mirrored_position(...)` resolves a mirrored record by that stored source-position key.

# 3a. REBALANCES (close my old + open at the source wallet's new range)
FOR each rb in rebalanced:
  my_pos = find_my_mirrored_position(rb["closed_id"])
  source_new_pos = find_position_by_id(current_positions, rb["new_id"])
  IF my_pos is None:
    IF auto_follow_new:
      pure_new.append(rb["new_id"])
      CONTINUE
    LOG "REBALANCE_NO_MIRRORED_POSITION"
    CONTINUE
  IF source_new_pos is None: WARN + LOG "SOURCE_REBALANCE_TARGET_MISSING". CONTINUE.

  IF auto_rebalance:
    1. byreal-cli --wallet-address <copier_wallet> positions close --nft-mint <my_pos.nft_mint> -o json
    2. SLEEP 5 seconds  ← balance needs time to settle
    3. actual_available = check_balance() (ACTUAL, not estimated)
       IF actual_available < 2 USDC: WARN + status "closed_pending_reopen". CONTINUE.
    4. Pool safety re-check on `source_new_pos.poolAddress`
       IF fails: HOLD funds + ALERT user. CONTINUE.
    5. rebalance_amount = min(actual_available * 0.95, my_pos.deposited_usd)
       IF rebalance_amount < 25 USDC: HOLD funds + ALERT user "Reopen amount too small after close". CONTINUE.
       Snap `source_new_pos.tickLower` / `source_new_pos.tickUpper` → swap for ratio (`byreal-cli --wallet-address <copier_wallet> swap execute ...`) → open position (`byreal-cli --wallet-address <copier_wallet> positions open --price-lower/--price-upper --amount-usd`)
       IF swap fails: retry once with 2x slippage. If still fails, try intermediate route (e.g. USDT→SOL→target). If all fail: HOLD funds + status "closed_pending_reopen" + ALERT user.
    6. UPDATE state with new position record
  ELSE:
    ALERT user: "Source wallet rebalanced. Follow? [Rebalance] [Keep] [Close]"

# 3b. PURE CLOSES
FOR each pos_id in pure_closed:
  my_pos = find_my_mirrored_position(pos_id)
  IF my_pos is None: CONTINUE
  IF auto_follow_close:
    byreal-cli --wallet-address <copier_wallet> positions close --nft-mint <my_pos.nft_mint> -o json
  ELSE: ALERT user

# 3c. PURE NEW OPENS (pair-filtered in pair mode)
IF follow_mode == "position": SKIP

FOR each pos_id in pure_new:
  new_pos = find_position_by_id(current_positions, pos_id)
  IF new_pos is None: CONTINUE
  new_pair = derive_pair(new_pos)
  IF pair mode AND new_pair != target_pair: CONTINUE

  # Empty position guard (Issue #2: source wallet may create an NFT with no liquidity)
  farmer_pos = new_pos
  position_age = derive_position_age(new_pos)
  defer_count = local_state.defer_counts.get(pos_id, 0)
  IF farmer_pos.liquidityUsd < 1.0:
    IF defer_count >= 3 OR (position_age is known AND position_age >= 10 min):
      LOG "SKIP_EMPTY: source-wallet position {pos_id} has no liquidity after repeated checks"
      CONTINUE
    IF position_age is unknown OR position_age < 10 min:
      local_state.defer_counts[pos_id] = defer_count + 1
      DEFER to next cycle (API cache may not have updated)
      CONTINUE

  IF auto_follow_new:
    source_position_pda = new_pos.positionAddress
    IF source_position_pda is missing:
      LOG "SKIP_NO_SOURCE_POSITION_PDA"
      ALERT user: "Detected a new source position, but the CLI response did not expose a copyable position address."
      CONTINUE
    Check max_positions cap
    Budget-aware allocation:
      remaining = max(0, max_total_usd - total_deployed - compound_reserve)
      IF multiple new this cycle: per_position = remaining / count
      Pool safety gate
      Actual balance check (per Position Budget Rules)
      IF open_amount < 100 USDC: SKIP + LOG "MIN_POSITION_NOT_MET"
      Execute copy using `source_position_pda`
  ELSE:
    ALERT user

### Step 4 — Stop-Loss Check (dynamic by pool type)
FOR each active position:
  # Adjust threshold by pool category
  IF stablecoin:  effective = min(stop_loss_pct, 5)     # depeg scenario
  ELIF major:     effective = stop_loss_pct              # user setting
  ELIF volatile:  effective = max(stop_loss_pct, 25)     # avoid whipsaw

  loss_pct = (entry - current) / entry * 100
  IF loss_pct >= effective:
    IF stop_loss_enabled: close + alert user
    ELSE: alert user only

### Step 5 — Compound Check
IF auto_compound:
  FOR each active position:
    Skip if: interval not elapsed, out of range, fees < threshold
    Gas guard: gas_cost_usd must be < max(fees_usd × 0.02, $0.01). I.e. gas must be under 2% of the fees being claimed, with a $0.01 floor.
    EXECUTE: claim fees → swap if imbalanced → `positions increase --nft-mint`

### Step 6 — Update Snapshot
IF position mode:
  Store reconciled active_positions from `positions list --user <copier_wallet>` as the source of truth for next cycle
  Persist `source_position_address`, optional `source_nft_mint`, `source_wallet_address`, `source_closed_at`, and pending user decision state
ELSE:
  Store reconciled active_positions for my mirrored wallet state
  Overwrite the tracked source wallet state with:
    last_snapshot = current_positions
    pair_index = positions indexed by pair
    last_checked = now()
    stale_count = 0
  Persist `defer_counts`

### Step 6b — Handle Pending User Decision (position mode)
IF local_state.pending_user_decision == "source_closed":
  WAIT for Telegram reply:
    [Keep monitoring]       -> clear pending decision, continue monitoring current active_positions
    [Close my copy]         -> close all current active_positions by nft_mint, clear pending decision
    [Pick a new position to copy]
                            -> IF current active_positions not empty:
                                 require explicit close first or convert action to:
                                 [Close my copy and pick a new one]
                               ELSE:
                                 clear pending decision
                                 run Startup Step 3 again to select a new source position
                                 re-run budget / max_positions checks
                                 execute a new copy cycle and persist the replacement:
                                   source_position_address
                                   source_nft_mint?
                                   source_wallet_address
                                   my_nft_mint
                                   pair
                                   pool
                                   tick_lower / tick_upper

### Step 7 — Source Wallet Quality + Health Report (daily)

  # Source wallet quality
  FOR each tracked_source_wallet:
    7d PnL < -5%           → WARN "underperforming"
    0 positions for 3+ days → DEACTIVATE + ALERT
    >10 rebalances in 7d   → WARN "excessive churn"

  # Write watchdog state — performance snapshot per AGENTS.md §Strategy Watchdog:
  #   strategy_name, status, budget_usd, current_value_usd, net_pnl_usd,
  #   net_pnl_percent, total_fees_earned_usd, total_costs_usd, days_active,
  #   last_report_at, alerts, effective_apy, il_percent, compound_count, copy_leader
  # Do NOT send messages to user. User-facing notifications are handled by byreal-watchdog.

### Step 8 — Alert Flag (Watchdog Integration)
  IF this cycle produced a new alert (stop-loss, source quality warning, etc.):
    Read ~/.openclaw/workspace/watchdog_state.json
    Set pending_alerts = true (atomic write: write .tmp then rename)

### Step 9 — Watchdog Health Check
  Read watchdog_state.last_heartbeat and watchdog_state.notify_interval
  IF now - last_heartbeat > 2 × notify_interval:
    → Watchdog may be down. Degrade to direct push: send this cycle's alerts to user via notification channel.
```

## Exit Conditions

| Condition | Action |
|-----------|--------|
| Stop-loss breached | Auto-close only if `stop_loss_enabled`; otherwise alert user only. |
| Budget cap reached | Block new opens. Existing continue. |
| Pool fails safety gate during rebalance | Withdraw funds, hold, alert user. |
| Price spike >20% in 1h | Pause `auto_follow_new` this cycle. Alert user. |
| Source wallet inactive 3+ cycles | Deactivate source wallet. Alert user. |
| User: "stop + close all" | Collect fees → close all → report final PnL. |
| Transient CLI/RPC failure | Per AGENTS.md §Error Handling: log, skip cycle, retry next loop. |

## Performance Metrics

- **Total capital deployed** vs `max_total_usd`
- **Open position count** vs `max_positions`
- **Total fees earned** + **total compounded**
- **Rebalance count** + cost per rebalance
- **Stop-loss exits** (count + total loss)
- **Follow latency** (source-wallet action → our mirror)
- **Time in range %** per position
- **Gas spent** (cumulative)
- **Net PnL** = fees + position value delta - gas - stop-loss losses

## Byreal CLI Commands

**Output parsing**: `-o json` returns **multi-line formatted JSON**. Do NOT use `grep '^{' | head -1` — it truncates the output. Instead, strip non-JSON lines first (e.g. `[CONFIRM]` prefixes), then parse the full JSON object.

**Execution mode note**:
- Main CLI (`@byreal-io/byreal-cli` `0.2.9`): write commands support `--confirm`.
- RealClaw (`@byreal-io/byreal-cli-realclaw` `0.3.3`): pass top-level `--wallet-address <address>` and treat write commands as unsigned-tx generation; no per-command `--confirm`.

**Key field names** (camelCase, not snake_case):

| Field | Description | Found in |
|-------|-------------|----------|
| `nftMintAddress` | Position NFT mint (unique ID) | `positions list`, `positions analyze` |
| `liquidityUsd` | Position value in USD | `positions list` (may be 0 for new positions — see Step 1 fallback) |
| `tickLower` / `tickUpper` | Tick range bounds | `positions list` |
| `poolAddress` | Pool the position belongs to | `positions list` |

Persist the identifiers according to current CLI semantics:
- `sourcePositionAddress`: source position PDA from `positions top-positions` / `positions copy`
- `sourceNftMintAddress`: original source NFT mint if exposed by `top-positions`; useful for wallet-poll matching and source-close detection
- `sourceWalletAddress`: source wallet address used with `positions list --user <wallet>` for monitoring the original/source wallet over time
- `nftMintAddress`: my copied position NFT mint, used for `positions analyze`, `positions increase`, `positions claim`, and `positions close`
- `positionAddress`: may appear in `positions list` output, but published management commands use `nftMintAddress`

```bash
# Discovery / analysis (both packages)
byreal-cli pools list --sort-field volumeUsd24h --sort-type desc --page-size 10 -o json
byreal-cli positions list --user <source_wallet_address> -o json
byreal-cli positions top-positions --pool <pool_address> --sort-field earned --status 0 -o json
byreal-cli pools analyze <pool_address> -o json

# Main CLI execute path (`@byreal-io/byreal-cli` 0.2.9)
byreal-cli positions copy --position <source_position_pda> --amount-usd <usd> --dry-run -o json
byreal-cli positions copy --position <source_position_pda> --amount-usd <usd> --confirm -o json
byreal-cli positions open --pool <pool> --price-lower <lo> --price-upper <hi> --amount-usd <usd> --confirm -o json
byreal-cli positions analyze <nft_mint_address> -o json
byreal-cli positions claim --nft-mints <nft_mint_address> -o json
# ⚠️ Use --nft-mints (NFT mint address), NOT --position (PDA). Using the PDA will fail silently.
byreal-cli positions increase --nft-mint <nft_mint_address> --amount-usd <usd> --confirm -o json
byreal-cli positions close --nft-mint <nft_mint_address> --confirm -o json
byreal-cli swap execute --input-mint <mint_in> --output-mint <mint_out> --amount <amt> --slippage <bps> --confirm -o json
byreal-cli wallet address -o json
byreal-cli wallet balance -o json

# RealClaw execute path (`@byreal-io/byreal-cli-realclaw` 0.3.3)
byreal-cli --wallet-address <wallet> positions copy --position <source_position_pda> --amount-usd <usd> -o json
byreal-cli --wallet-address <wallet> positions open --pool <pool> --price-lower <lo> --price-upper <hi> --amount-usd <usd> -o json
byreal-cli positions analyze <nft_mint_address> -o json
byreal-cli --wallet-address <wallet> positions claim --nft-mints <nft_mint_address> -o json
byreal-cli --wallet-address <wallet> positions increase --nft-mint <nft_mint_address> --amount-usd <usd> -o json
byreal-cli --wallet-address <wallet> positions close --nft-mint <nft_mint_address> -o json
byreal-cli --wallet-address <wallet> swap execute --input-mint <mint_in> --output-mint <mint_out> --amount <amt> --slippage <bps> -o json
byreal-cli wallet balance -o json
```

## Example Configurations

### Conservative — Single position (position mode)
```yaml
follow_mode: position
amount_usd: 100
max_total_usd: 100
compound_threshold: 5
compound_interval: 24h
monitor_interval: 15m
stop_loss_enabled: true
stop_loss_pct: 15
max_positions: 1
max_source_wallets: 1
auto_compound: true
auto_follow_new: false
auto_follow_close: true
auto_rebalance: false
slippage_tolerance: 1.0
```

### Balanced — Track source wallet on one pair (pair mode)
```yaml
follow_mode: pair
target_pair: SOL/USDC     # auto-set from initial position
amount_usd: 100
max_total_usd: 500
compound_threshold: 3
compound_interval: 12h
monitor_interval: 10m
stop_loss_enabled: true
stop_loss_pct: 20
max_positions: 5
max_source_wallets: 1
auto_compound: true
auto_follow_new: true
auto_follow_close: true
auto_rebalance: true
slippage_tolerance: 1.0
```

### Aggressive — Full address tracking (address mode)
```yaml
follow_mode: address
amount_usd: 200
max_total_usd: 2000
compound_threshold: 2
compound_interval: 6h
monitor_interval: 10m
stop_loss_enabled: true
stop_loss_pct: 25
max_positions: 10
max_source_wallets: 1
auto_compound: true
auto_follow_new: true
auto_follow_close: true
auto_rebalance: true
slippage_tolerance: 1.5
```

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| **Execution lag** | Medium | `monitor_interval` controls max lag |
| **Adverse selection** | Medium | Select consistent farmers, not one-day spikes |
| **Rebalance cost** | Medium | Gas cheap on Solana, health report tracks total cost |
| **Rebalance balance race** | Low-Medium | 5s SLEEP + actual balance check after close |
| **API cache stale data** | Medium | Stale-cache detection, optional RPC cross-check |
| **Wallet balance exhausted** | Medium | Position Budget Rules: 60/40 split, compound reserve |
| **Stop-loss whipsaw** | Low-Medium | Dynamic by pool type: stable 5%, major user-set, volatile 25% |
| **Source wallet underperforms** | Medium | Daily quality check: 7d PnL, rebalance frequency |
| **Pool safety failure** | Low | Re-checked on every open and rebalance |

## Known V1 Limitations

1. **Single-cycle rebalance detection**: If the source wallet does 2 rebalances within one `monitor_interval`, only the final state is visible. V2 may add tx history fallback via `getSignaturesForAddress`.
2. **Cross-pool migration not detected**: close USDC/USDT + open USDC/USD1 classified as EXIT + NEW, not MIGRATION. Acceptable with only 2 stablecoin pools.
3. **REFERER_POSITION memo**: SDK injects a Memo instruction for analytics. If missing (SDK change or CU limit), still open the position — log `referer_verified: false`. Never block a trade over a missing memo.
