---
name: byreal-stable-yield-farm
version: 0.1.0
description: "Stablecoin concentrated LP yield strategy (USDC/USDT, USDC/USD1). Auto-compound fees, depeg monitoring, data-driven range presets. Use when user wants stable yield, stablecoin LP, or low-risk farming."
---

# Strategy: Stablecoin Yield Farm

> Earn steady yield by providing concentrated liquidity on stablecoin pairs with tight ranges and auto-compounding.
>
> **Depends on**: AGENTS.md §User Permission Model, §Risk Limits (slippage, gas reserve), §Strategy Watchdog, §Error Handling.

## Overview

| Attribute | Value |
|-----------|-------|
| Category | LP — Yield Optimization |
| Risk | Conservative (C) |
| Complexity | ** Multi-step |
| Market | Stablecoin pairs only — low directional exposure, but depeg and protocol risk remain |
| Cycle | D-W |
| Min Capital | 200 USDC recommended for Safe tier; 100 USDC absolute minimum |

## Supported Pools (MVP)

| Pair | Reference APR | Notes |
|------|-------------|-------|
| USDC/USDT | 3–8% | Highest volume stablecoin pair on Byreal |
| USDC/USD1 | 3–6% | Byreal-native stablecoin pair |

V1 is allowlist-only: `USDC/USDT` and `USDC/USD1`.
Do not auto-discover, auto-migrate, or auto-enter new pools in v1. Additional pools require an explicit allowlist update and fresh user approval.

## Range Selection — Data-Driven Defaults

> Based on 90-day daily + 30-day hourly USDC/USDT price analysis (March 2026), with 2.5x on-chain variance buffer applied.

### Price Distribution Summary (USDC/USDT relative price, 30 days hourly)

```
Mean:              0.999965
Median:            0.999952
Std (aggregated):  1.5 bps
Std (on-chain est):3.7 bps  (2.5x buffer for DEX-specific variance)
Max deviation:     5.3 bps from 1.0

90-day USDT/USD tail risk:
  Min price: 0.9980 (20 bps off peg)
  Days below 0.9990: 21/91
  Days below 0.9985: 3/91
  Days below 0.9980: 1/91

100% of 30-day observations fell within [0.9995, 1.0005] (10 bps).
On-chain pools see 2-3x more variance due to swap impact + arb lag.
```

### Range Presets

| Preset | Range | Width | Coverage | Capital Efficiency | Use Case |
|--------|-------|-------|----------|-------------------|----------|
| **Tight** | [0.9990, 1.0010] | 20 bps | ~99.3% (2.7σ) | ~10x | Active monitoring. Highest fee capture. May go out of range during volatility spikes. |
| **Default** | [0.9985, 1.0015] | 30 bps | ~99.99% (4σ) | ~7x | Balanced. Rarely goes out of range. Good for most users. |
| **Conservative** | [0.9978, 1.0022] | 44 bps | ~100% (6σ) | ~5x | Set and forget. Covers all 90-day observations including tail events. |

### Selection Logic

```
IF user risk tier == "Safe" OR user is new:
  → Conservative preset [0.9978, 1.0022]
IF user risk tier == "Balanced":
  → Default preset [0.9985, 1.0015]
IF user risk tier == "Aggressive" OR user requests max yield:
  → Tight preset [0.9990, 1.0010]
  → WARN: "Tight range earns ~2x more fees but may need rebalancing during volatility."

IF Byreal pool kline data is available:
  → Override with pool-specific analysis:
    1. Fetch 30d hourly klines for the specific pool
    2. Compute P2.5 and P97.5 of price distribution
    3. Apply 1.5x buffer beyond those percentiles
    4. Use as range bounds
```

### Capital Efficiency Reference

Narrower range = more concentrated liquidity = higher fee capture per dollar.

```
 5 bps range → ~40x efficiency (extremely tight, constant rebalancing)
10 bps range → ~20x efficiency
20 bps range → ~10x efficiency  ← Tight preset
30 bps range →  ~7x efficiency  ← Default preset
44 bps range →  ~5x efficiency  ← Conservative preset
```

Capital efficiency multiplier means your liquidity is more concentrated than a full-range position.
Actual yield depends on pool volume, existing liquidity distribution, and time in range.
Do NOT multiply pool APR × efficiency — pool APR already reflects current LP concentration.

## Requires

```yaml
feeds:
  - pool-state          # current price, fee_24h, apr_24h, tvl
  - position            # unclaimed fees, range status, IL, PnL
  - external-price      # absolute USD peg check for each stablecoin if available

execution:
  - add-liquidity       # open position with tight stablecoin range
  - collect-fees        # harvest accrued fees
  - swap                # rebalance fee tokens for compounding
  - remove-liquidity    # exit position (full or partial)
  - rebalance           # re-center range on depeg drift (rare)

risk:
  - gas-check           # ensure gas < fee value before compounding
  - il-threshold-alert  # alert when IL exceeds the configured threshold for this strategy
  - rebalance-cooldown  # prevent excessive rebalancing when auto_rebalance enabled
  - allowlist-check     # pool/protocol must be approved for v1
```

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `pool` | string | `USDC/USDT` | required, must be stablecoin pair | Pool address or token pair |
| `range_preset` | enum | `default` | `tight` / `default` / `conservative` | Selects from data-driven range presets (see Range Selection above) |
| `range_lower` | number | `0.9985` | `0.9900–0.9999` | Lower price bound. Auto-set by preset, can be overridden. |
| `range_upper` | number | `1.0015` | `1.0001–1.0100` | Upper price bound. Auto-set by preset, can be overridden. |
| `deposit_amount` | number | — | required, `>= 100` | Total USDC-equivalent to deposit |
| `compound_threshold` | number | `1` | `0.50–100` | Minimum unclaimed fees (USDC) to trigger compound |
| `compound_interval` | duration | `12h` | `1h–7d` | How often to check fees for compounding |
| `monitor_interval` | duration | `1h` | `5m–6h` | How often to check position health |
| `il_alert_pct` | number | `3.0` | `0.5–20.0` | Alert threshold for impermanent loss percent. Stablecoin IL should normally stay low; alert instead of auto-exiting. |
| `depeg_warn` | number | `0.0050` | `0.0010–0.0200` | Deviation from 1.0 that triggers warning (both directions). 0.0050 = 50 bps. |
| `depeg_exit` | number | `0.0100` | `0.0030–0.0300`, must be > `depeg_warn` | Deviation from 1.0 that triggers emergency exit. 0.0100 = 100 bps. |
| `slippage_tolerance` | number | `0.3` | `0.1–0.5` | Max slippage percent (AGENTS.md §Risk Limits stablecoin tier: 0.1–0.5%) |
| `auto_compound` | bool | `true` | — | Enable automatic fee reinvestment |
| `rebalance_cooldown` | duration | `4h` | `1h–48h` | Minimum time between rebalances (only used when `auto_rebalance` is true) |
| `auto_rebalance` | bool | `false` | — | Auto-rebalance on minor drift (not recommended for stables) |
| `emergency_exit_mode` | enum | `withdraw_and_pause` | `withdraw_and_pause` / `withdraw_and_swap_if_safe_preapproved` | Default is to remove liquidity and pause. Only swap after exit if an oracle-backed safe side is already approved in the active strategy permission. |

## Scheduler And Runtime State

This strategy is driven by one isolated scheduler job per strategy instance.

- Register one `openclaw cron` job at strategy start, named `byreal-stable-yield-farm-<strategy_id>`.
- Run it every `monitor_interval`.
- The cron executor must read this skill, load the strategy runtime state, run one monitoring cycle, and then persist updated state.

Example registration:

```bash
openclaw cron add \
  --name byreal-stable-yield-farm-<strategy_id> \
  --every <monitor_interval> \
  --session isolated \
  --timeout-seconds 600 \
  --message "Stable Yield Farm executor. Read the skill file at ~/.openclaw/workspace/skills/byreal-stable-yield-farm/SKILL.md, load this strategy's runtime state, run one monitoring cycle, persist state, and report alerts."
```

Persist these watchdog fields in the strategy runtime state so AGENTS.md §Strategy Watchdog can monitor health:

- `last_heartbeat`
- `current_step`
- `last_success_at`
- `retry_count`

Recommended recurring state fields:

- `last_monitor_at`
- `last_compound_at`
- `last_rebalance_at`
- `compound_count`
- `alerts`

## Position Budget Rules

- Before opening, compute deployable capital from settled wallet balances only.
- Keep `gas_reserve = 0.02 SOL` (stricter than the 0.01 SOL agent-wide minimum in AGENTS.md §Risk Limits; extra buffer for multi-step compound + rebalance operations).
- Keep `rebalance_buffer = max(2 USDC, 5% of intended strategy budget)` for ratio swaps, reopen costs, and small balance drift.
- Compute `available = settled_wallet_value - gas_reserve_value - rebalance_buffer`.
- Set `max_position_size = min(deposit_amount, available)`. Do not size the LP position above actual available capital.
- On rebalance, always: `close -> wait for funds to settle -> re-read actual balances -> recalculate available -> reopen`.
- Never assume pre-close balances when reopening. Use only post-close settled balances.

## Required Preapproval At Strategy Start

Before deploying this strategy, ask the user how depeg emergencies should be handled. Capture the answer in the active strategy permission.
This preapproval should be shown in both the Console strategy setup flow and in Telegram. Approval from either surface is valid, but the recorded setting must sync across both.

Default prompt:

> If one stablecoin depegs, I will remove liquidity immediately. What should I do next?
> 1. Withdraw and pause (Recommended)
> 2. Withdraw and auto-swap the depegged side into the approved safe side, but only if oracle checks confirm it

Rules:

- If the user does not explicitly opt into option 2, use `withdraw_and_pause`.
- Option 2 only applies to the approved pool and approved token pair for this strategy.
- Option 2 does not authorize migration into a new pool or strategy.
- If the user later changes this setting, treat it as a strategy-permission update and confirm again.
- Console and Telegram must show the same current `emergency_exit_mode` value.
- If the user approves in one surface, the other surface should reflect the updated setting immediately.

## Decision Logic

### Execution Reliability

Use a simple checkpointed flow for every multi-step action:

`precheck -> swap -> verify_balances -> add_liquidity -> verify_position -> done`

Rules:

- Do not advance to the next step until the prior step is confirmed on-chain or via Byreal CLI state.
- Write a checkpoint after each successful step so retries resume from the last known-good state.
- Retry a failed execution step up to 3 times with backoff. If still failing, pause the strategy and alert the user.
- If `swap` succeeds but `add_liquidity` fails, hold the split assets, mark the workflow as partial, and ask the user whether to retry LP entry or unwind.
- If `collect-fees` succeeds but reinvestment fails, keep claimed fees in the wallet and retry on the next eligible cycle.
- After any timeout or RPC uncertainty, re-read balances/position state before retrying to avoid duplicate actions.

```
## Startup

0. GAS CHECK:
   IF wallet SOL < 0.01 SOL: BLOCK startup + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"

1. VALIDATE pool is a stablecoin pair (both tokens should be stable-pegged assets)
2. VALIDATE depeg_warn < depeg_exit (warn threshold must be stricter than exit threshold)
3. VALIDATE pool is in the v1 allowlist (`USDC/USDT`, `USDC/USD1`) and is covered by the active strategy permission
4. FETCH pool_state → current_price, fee_rate, apr_24h, tvl, volume_24h, protocol
5. VALIDATE protocol is approved in the active strategy permission
6. VALIDATE emergency_exit_mode is explicitly captured in the active strategy permission
7. VALIDATE current_price is within 0.5% of 1.0 (reject if already depegged)
8. VALIDATE tvl >= 50,000 USDC (minimum pool depth for safety)
9. WARN user if volume_24h / tvl is unusually weak for a stablecoin pool
10. FETCH external absolute USD prices for both tokens if available
11. RECORD whether oracle-backed emergency swap is available for this pool
12. RESOLVE range from preset (if not manually overridden):
     IF range_preset == "tight":        range = [0.9990, 1.0010]
     IF range_preset == "default":      range = [0.9985, 1.0015]
     IF range_preset == "conservative": range = [0.9978, 1.0022]
   IF pool-specific kline data available:
     FETCH 30d hourly klines → compute P2.5/P97.5 → apply 1.5x buffer → use as range
   SNAP range bounds to valid tick spacing for the pool (pool_state.tick_spacing)
   IF snapped range width differs from preset width by > 20%:
     → WARN user: "Pool tick spacing forces range adjustment. Effective range: [{snapped_lower}, {snapped_upper}]"
13. CHECK for existing position in same pool:
     IF position exists AND in_range:
       → ASK user: "You already have a position in this pool. Add to it or open new?"
     IF position exists AND NOT in_range:
       → ASK user: "Existing position is out of range. Rebalance it or open new?"
14. CALCULATE token split:
     - Use current_price + range bounds to compute target ratio
     - token_a_amount = deposit_amount * ratio_a
     - token_b_amount = deposit_amount * ratio_b
15. BALANCE CHECK + swap if needed:
     IF user has only token_a: swap(token_b_amount worth of token_a → token_b, slippage_tolerance)
     IF user has only token_b: swap(token_a_amount worth of token_b → token_a, slippage_tolerance)
     IF user has both but wrong ratio: swap the excess side to match target ratio
16. EXECUTE add-liquidity(pool, range_lower, range_upper, token_a, token_b)
17. LOG position opened: pool, range, deposit, position_address, emergency_exit_mode

## Monitoring Loop

EVERY monitor_interval:

1. FETCH pool_state → current_price, tvl, apr_24h, volume_24h
2. FETCH position → { in_range, unclaimed_fee_a, unclaimed_fee_b, il_percent,
                       position_value_usd, fees_earned_usd }
   FETCH external absolute USD prices for both tokens if available

3. DEPEG CHECK (stablecoin-specific, both directions):
     deviation = |current_price - 1.0|
     IF deviation > depeg_warn AND deviation <= depeg_exit:
       → WARN user: "Price at {current_price} ({deviation*10000:.0f} bps off peg). Monitoring closely."
     IF deviation > depeg_exit:
       → EMERGENCY EXIT:
         a. remove-liquidity(position_id, 100%)
         b. IF external absolute USD prices are available AND exactly one token is still
              within the approved peg band AND emergency_exit_mode == withdraw_and_swap_if_safe_preapproved
              AND the active strategy permission already allows that post-exit swap:
              → swap only the clearly depegged token into the approved safe token
              → ALERT user: "Emergency exit — {depegged_token} at {price}. Funds converted to {safe_token} per pre-approved safety rule."
            ELSE:
              → HOLD withdrawn assets as-is
              → ALERT user: "Emergency exit — price moved {deviation*10000:.0f} bps off peg. Liquidity removed and strategy paused. Manual review required."
         c. STOP strategy
       → RETURN
     NOTE: This check uses relative price (token_a/token_b). If both tokens depeg
     simultaneously (e.g., regulatory event), the relative price may stay near 1.0.
     Relative price alone is not enough to pick a safe side. External absolute USD
     prices are required before any post-exit swap into a presumed "safe" token.

4. POSITION EXISTS CHECK:
     IF position not found (closed externally or liquidated):
       → ALERT user: "Position no longer exists. Strategy stopped."
       → STOP strategy
       → RETURN

5. TVL CHECK:
     IF tvl < 50,000 USDC:
       → WARN user: "Pool TVL dropped below 50k ({tvl}). Low liquidity — consider migrating."
       → Continue monitoring (do not auto-exit, but inform user)
     IF volume_24h / tvl is unusually weak for 3+ daily samples:
       → WARN user: "Pool activity is weak relative to liquidity. Fee opportunity may be deteriorating."

6. RANGE CHECK:
     IF NOT in_range:
       → LOG "Position out of range at price {current_price}"
       → IF auto_rebalance:
            CHECK rebalance_cooldown → if last rebalance was < rebalance_cooldown ago, HOLD + log "cooldown active"
            CALCULATE new range centered on 1.0 (the peg) using same preset width
              (center on peg, NOT on current_price — for stablecoins we expect reversion)
            SNAP to valid tick spacing
            rebalance(position_id, new_lower, new_upper)
            LOG rebalance: old_range, new_range, cost
         ELSE:
            → WARN user: "Position out of range. Earning zero fees. Rebalance?"
              → [Rebalance now] [Widen range] [Keep waiting]

7. IL CHECK:
     IF il_percent > il_alert_pct:
       → ALERT user: "IL at {il_percent}%. Exceeds the configured alert threshold ({il_alert_pct}%). Consider reviewing or exiting."
       → Do not auto-exit (stablecoin IL is usually transient), but pause compounding.

8. COMPOUND CHECK (if auto_compound enabled AND in_range AND il_check passed):
     Skip if out of range — compounding into a position earning zero fees wastes gas.
     If rebalance occurred in step 6 this cycle, defer compounding to the next cycle.
     IF interval since last compound >= compound_interval:
       a. CALCULATE total_fees_usd = unclaimed_fee_a * price_a + unclaimed_fee_b * price_b
       b. IF total_fees_usd < compound_threshold:
            → HOLD (fees too small)
       c. CHECK gas-check → if estimated gas cost > 2% of total_fees_usd (or > 5 USDC absolute), HOLD (not worth it)
       d. EXECUTE compound:
            1. collect-fees(position_id)
            2. Calculate target ratio for current range
            3. IF ratio imbalanced: swap(excess → deficit, slippage_tolerance)
            4. add-liquidity(pool, range_lower, range_upper, token_a, token_b)
       e. LOG compound: fees_collected, fees_reinvested, gas_cost

9. APR CHECK (daily):
     Track apr_24h in rolling 7-day window.
     IF apr_24h < 1% for 7+ consecutive daily samples:
       → WARN user: "Yield too low (APR {apr_24h}% for 7+ days). Consider migrating to another approved pool with fresh user approval."

10. HEALTH REPORT (daily, or on user request):
     → Position value, total fees earned, net PnL, current APR, IL%, time in range

11. REPORT TO WATCHDOG (every cycle):
     Push performance snapshot per AGENTS.md §Strategy Watchdog:
       strategy_name: "Stablecoin Yield Farm"
       status, budget_usd, current_value_usd: position_value_usd + uninvested balance
       net_pnl_usd: fees_earned_usd - total_gas_spent - il_value
       net_pnl_percent: net_pnl_usd / budget_usd * 100
       total_fees_earned_usd, total_costs_usd: cumulative gas + swap fees
       days_active, last_report_at: now
       effective_apy, time_in_range_pct, il_percent, compound_count
       alerts: collect any active warnings from steps 3-9
       # This step ONLY writes runtime state. Do NOT send messages to user.
       # User-facing notifications are handled by byreal-watchdog.
```

### Post-Cycle: Watchdog Integration

After completing the monitoring cycle:

```
12. Alert flag: IF this cycle produced a new alert (depeg warning, IL alert, out-of-range, etc.):
      Read ~/.openclaw/workspace/watchdog_state.json
      Set pending_alerts = true (atomic write: write .tmp then rename)

13. Watchdog health check:
      Read watchdog_state.last_heartbeat and watchdog_state.notify_interval
      IF now - last_heartbeat > 2 × notify_interval:
        → Watchdog may be down. Degrade to direct push: send this cycle's alerts to user via notification channel.
```

## Exit Conditions

| Condition | Action |
|-----------|--------|
| Deviation exceeds `depeg_exit` | Auto-exit liquidity removal. Swap only if oracle-backed safe side is pre-approved; otherwise pause and alert user |
| IL exceeds `il_alert_pct` | Alert user, suggest exit |
| Pool TVL drops below 50k | Warn user: low liquidity, suggest migration |
| APR drops below 1% for 7+ days | Warn user: "Yield too low, consider migrating to higher-APR pool" |
| User requests stop + exit | Collect fees → remove liquidity → return tokens to wallet |
| User requests stop (keep position) | Stop monitoring loop. Position remains open and earns fees but is unmanaged. |

## Performance Metrics

Track and report:
- **Total fees earned** (cumulative USDC)
- **Compound count** and total compounded value
- **Effective APY** (actual realized, including compound effect vs simple APR)
- **Time in range %** (should be >99% for stablecoins)
- **IL %** (should be near zero for stablecoins)
- **Total gas spent** (compound + rebalance costs)
- **Net P&L** = fees earned - gas costs - IL
- **Days active**

## Byreal CLI Commands

Primary runtime is RealClaw CLI `0.3.3`. Use `--wallet-address <agent_wallet_address>` for all write commands.

```bash
# List pools (read-only, no --wallet-address needed)
byreal-cli pools list --sort-field apr24h --sort-type desc -o json

# Analyze a specific pool (read-only)
byreal-cli pools analyze <pool_address> -o json

# Open position (write — --amount-usd auto-calculates token split)
byreal-cli --wallet-address <agent_wallet_address> positions open --pool <address> \
  --price-lower <range_lower> --price-upper <range_upper> \
  --amount-usd <deposit_amount> --slippage <bps> -o json

# Check position status (read-only)
byreal-cli positions analyze <nft_mint_address> -o json

# Collect fees (write)
byreal-cli --wallet-address <agent_wallet_address> positions claim --nft-mints <nft_mint_address> -o json

# Close position (write)
byreal-cli --wallet-address <agent_wallet_address> positions close --nft-mint <nft_mint_address> -o json

# Swap for ratio balancing (write, slippage in basis points: 30 = 0.3%)
byreal-cli --wallet-address <agent_wallet_address> swap execute \
  --input-mint EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v \
  --output-mint Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB \
  --amount <amount> --slippage 30 -o json
```

## Example Configurations

### Conservative — Safe tier / new users (set and forget, 5x efficiency)
```yaml
pool: USDC/USDT
range_preset: conservative
# range auto-set to [0.9978, 1.0022] — 44 bps, covers 100% of 90d observations
deposit_amount: 500
compound_threshold: 5
compound_interval: 24h
monitor_interval: 4h
depeg_warn: 0.0050    # 50 bps
depeg_exit: 0.0100    # 100 bps
auto_compound: true
auto_rebalance: false
```

### Default — Balanced tier (7x efficiency, rarely out of range)
```yaml
pool: USDC/USDT
range_preset: default
# range auto-set to [0.9985, 1.0015] — 30 bps, 99.99% coverage
deposit_amount: 200
compound_threshold: 1
compound_interval: 12h
monitor_interval: 1h
depeg_warn: 0.0050    # 50 bps
depeg_exit: 0.0100    # 100 bps
auto_compound: true
auto_rebalance: false
```

### Tight — Aggressive tier / max yield (10x efficiency, monitor for out-of-range)
```yaml
pool: USDC/USDT
range_preset: tight
# range auto-set to [0.9990, 1.0010] — 20 bps, ~99.3% coverage
deposit_amount: 200
compound_threshold: 1
compound_interval: 6h
monitor_interval: 30m
depeg_warn: 0.0050    # 50 bps
depeg_exit: 0.0100    # 100 bps
auto_compound: true
auto_rebalance: true   # tight range may drift — auto-rebalance when out of range
rebalance_cooldown: 4h
```

### USDC/USD1 variant
```yaml
pool: USDC/USD1
range_preset: default
# USD1 is newer — less price history. Use default preset with slightly tighter depeg thresholds.
deposit_amount: 200
compound_threshold: 1
compound_interval: 12h
monitor_interval: 1h
depeg_warn: 0.0040    # 40 bps — tighter for newer stablecoin
depeg_exit: 0.0080    # 80 bps
auto_compound: true
auto_rebalance: false
```

## Interaction with Other Strategies

| Strategy | Combo Behavior |
|----------|---------------|
| Auto Compound (external) | Redundant — this strategy has compounding built in. Do not stack. |
| IL Monitor + Auto Exit (external) | Compatible as a secondary safety net. Set IL Monitor thresholds wider than the depeg thresholds here. |
| Pool Rotation (external) | Compatible only inside the v1 allowlist and only with fresh user approval before migration. |

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| **Depeg** — one stablecoin loses its peg | Low but catastrophic | `depeg_exit` auto-exits. Monitor price every `monitor_interval`. |
| **Smart contract exploit** | Low | Byreal contracts audited. Diversify across pools if capital allows. |
| **Low yield** | Medium | APR varies with volume. Consider migration only within the approved allowlist and only with fresh user approval. |
| **Out of range** | Very low (stablecoins) | Data-driven presets cover 99.3%–100% of observations. Auto-rebalance available if needed. |
| **Correlated depeg** — both stablecoins lose peg simultaneously | Very low but severe | Relative price stays near 1.0; `depeg_exit` may not trigger. Rely on external absolute-price monitoring and manual review. |
| **Gas exceeds fees** | Low (Solana gas is cheap) | `gas-check` guard prevents unprofitable compounds. |

## Notes

- Stablecoin LP is a lower-volatility yield strategy on Byreal, but it still carries depeg, protocol, and automation risk. Good fit for the "Safe" tier when users explicitly want yield rather than pure cash parking.
- Earnings estimate: pool APR is only a rough operating signal. Concentrated positions may earn more or less than full-range LP depending on fee flow, liquidity distribution, time in range, and rebalance costs. Show users realized fees and net P&L, not promotional projections.
- The `auto_rebalance` default is `false` because stablecoin prices rarely leave tight ranges. Rebalancing costs (swap fees + gas) can exceed the benefit. Only enable for pools showing persistent drift.
- Always use `-o json` flag with Byreal CLI for structured output that the agent can parse.
