---
name: byreal-dca
version: 0.1.0
description: |
  Use this skill whenever the user wants to set up recurring token buys on Solana (DCA), check the status of existing DCA plans, or manage them — including adding funds, adjusting amounts/frequency, pausing, resuming, cancelling, or selling/exiting positions. Trigger on phrases like "DCA into ...", "buy ... every day", "DCA status", "pause my DCA", "sell my holdings", "exit my position", or any mention of recurring buys, dollar-cost averaging, or managing an existing Byreal DCA plan.
metadata:
  openclaw:
    emoji: "📈"
---

# Strategy: Byreal DCA

> **Depends on**: AGENTS.md §Wallet, §Transaction Safety, §User Permission Model, §Risk Limits, §Error Handling.

Recurring buy manager for Byreal. Simple by default, recommendation-first, verify before claiming success, ask before any sell.

Two modes: **Smart DCA** (whitelist tokens — auto strategy, exit monitoring) and **Basic DCA** (non-whitelist token / mint / manual params).

- Whitelist token + budget → Smart DCA
- Non-whitelist token, mint address, or manual-control intent → Basic DCA

### Whitelist Tokens

See `references/whitelist-tokens.md` for the full token list with mint addresses and yfinance tickers. Only whitelist tokens get auto mode selection (SMA check), Smart Exit monitoring, and recommended defaults. Any other token/mint → Basic DCA.

---

## Available Tools

| Tool | Purpose | Command |
|------|---------|---------|
| Market Regime Check | SMA200 signal → buy mode | `python3 {baseDir}/references/sma_check.py <TOKEN> --ma 200` |
| Swap | Buy or sell tokens | `byreal-cli swap execute` (dry-run first, then write) |
| Stable Pool Position | Park idle USDC for yield | `byreal-cli positions open/decrease/increase/close/claim` |
| Config Manager | Read/write plan state | `configs/dca/<TOKEN>.json` (relative to workspace root) |

Full config schema: `references/config-schema.md`. Full CLI docs: `byreal-cli skill`. `{baseDir}` is resolved by OpenClaw to this skill's directory path.

### Operational Notes

- **SMA signal mapping** (default): `above` → Standard, `below` → Defensive (30%), `unavailable` → Standard (fallback). Cache: one check per day per plan.
- **Risk tier override**: If USER.md `risk_tier` = `aggressive`, auto-select Aggressive mode instead of the SMA-based default. SMA check still runs (used by exit monitoring), but mode is always Aggressive. If `risk_tier` = `safe`, cap at Standard even when SMA is above (no Aggressive allowed without tier switch).
- **Swap `--amount` is UI format** (20 = $20 USDC). `--slippage` is basis points (100 = 1%). CLI auto-resolves decimals.
- **Stable pools require BOTH USDC and USDT**. Swap half to USDT before opening. Only for plans with budget ≥ $1,000. Pools: `HrWp3QR3hNeVy6tEZtcpsjwEiGgKJuL1NDP84EaaU2Nh`, `23XoPQqGw9WMsLoqTu8HMzJLD6RnXsufbKyWPLJywsCT` — use the one with higher TVL. Open with `--price-lower 0.99 --price-upper 1.01` (stablecoin range).
- **`remaining_usdc` only decreases by confirmed buy spend** — never by LP operations, wallet buffer changes, or parking.

### Config Status Table

| Status | Cron does | User sees |
|--------|----------|-----------|
| `active` | Execute buy | "On Track" |
| `paused` | Skip | "Paused" |
| `attention_required` | Skip, notify | "Needs Attention" + reason |
| `holding_only` | Skip buy, monitor exit | "Holding (no more buys)" |
| `completed` | Skip | "Completed" |
| `cancelled` | Skip | "Cancelled" |

---

## Config Path — MANDATORY

All plan configs live in **`configs/dca/`** under the workspace root (`~/.openclaw/workspace/configs/dca/`). Create the directory if missing (`mkdir -p ~/.openclaw/workspace/configs/dca`). Cron reads exclusively from this path; configs stored elsewhere will be invisible to the executor.

## Workflow: Create Plan

### Phase 1 — Pre-flight

Run `mkdir -p ~/.openclaw/workspace/configs/dca` then check for existing config for the same token.

- Active plan exists → **do NOT create a second one**. Offer: add funds / modify / cancel and start fresh.
- No active plan → proceed.

### Phase 2 — Gather

**When user provides token + budget** → go directly to step 1 below.

**When user intent is vague** ("I want to DCA", "help me DCA", no token/budget specified):
Do NOT ask 4 separate questions. Instead, auto-recommend:

```
1. Check wallet USDC balance  → byreal-cli --wallet-address <agent_wallet_address> wallet balance -o json
2. Get token prices            → byreal-cli tokens list -o json
3. Pick default recommendation:
   → Token: SPYx or XAUt0 (stable long-term assets; prefer SPYx for equity exposure, XAUt0 for gold hedge — pick based on user context, default SPYx)
   → Budget: 80% of wallet USDC (round down to nearest $5, leave buffer for gas)
   → Daily amount: from budget table below
   → Mode: from SMA check
4. Present ONE recommendation with rationale → go to Phase 3 Confirm
   Example: "You have $42 USDC. Recommended: SPYx DCA, $40 budget, $5/day × 8 days, Standard mode. Confirm?"
   User can adjust any parameter in their reply.
```

**Smart DCA** — token + total budget known:

```
1. Identify token     → byreal-cli tokens list -o json
                         Whitelist token → Smart DCA
                         Non-whitelist token or mint address → Basic DCA
2. Market check       → python3 {baseDir}/references/sma_check.py <TOKEN> --ma 200
                         above → Standard | below → Defensive
   Risk tier override  → Read USER.md risk_tier field:
                         aggressive → Aggressive (regardless of SMA signal)
                         safe → cap at Standard (never Aggressive)
                         balanced/missing → use SMA-based default above
3. Daily amount:
   | Budget       | Amount/Day |
   |-------------|-----------|
   | < $100      | $5        |
   | $100–500    | $10       |
   | $500–2,000  | $20       |
   | $2,000–10k  | $50       |
   | $10,000+    | $100      |
4. For SOL → ask once if user wants bbSOL yield on holdings
```

**Basic DCA** — user provides mint/token + amount + frequency:

```
1. Collect: token or mint + amount + frequency
2. If incomplete → ask ONE question: "How much and how often? e.g. $20/day or $100/week"
3. No auto mode, no Smart Exit
```

### Phase 3 — Confirm

Show plan summary. Ask for ONE confirmation. See Response Formats: Plan Confirmation.

Defensive: show both amounts — "Base: $20/day, Defensive (current): $6/day — price is below SMA200."
Aggressive (only if user requests): show reserve calculation.

### Phase 4 — Execute

On confirmation, execute ALL steps in order. Do NOT skip any.

```
0. Gas check (AGENTS.md §Risk Limits) → STOP if below reserve
1. Dry-run swap USDC → token for daily_amount → check price impact (>1% abort, >0.2% warn)
2. Execute swap → verify buy landed by re-reading balances
3. If bbSOL enabled (SOL only) → convert SOL → bbSOL
4. Park idle funds in stable pool (only if budget ≥ $1,000, swap half to USDT first)
   → Save position_id in config. If fails → funds stay in wallet, plan still active.
   → If budget < $1,000: set `idle_yield.pool_address = null` and `idle_yield.position_id = null`.
5. Save config to ~/.openclaw/workspace/configs/dca/<TOKEN>.json
6. Register cron if not already registered (see below)
```

Config write rules:
- If first buy landed and post-checks match: `remaining_usdc = total_budget - actual_buy_spend_usdc`, and append the confirmed buy to `execution_log`
- If first buy did not land or the post-check is ambiguous: `remaining_usdc = total_budget`, and leave `execution_log` empty
- LP parking amount does not reduce `remaining_usdc`

### Phase 5 — Verify

```
1. Read back saved config → confirm it parses correctly
2. Check cron → openclaw cron list --json | grep byreal-dca
3. Update USER.md §Active Strategies with the new plan (ID, strategy name, status, budget)
4. Report: "Plan created. First buy: 0.135 SOL at $148.20. Next buy: Mar 26, 2026 10:00 UTC."
```

### Cron Registration

One cron serves ALL plans. Register on first plan creation only.

Each cron run must update the watchdog fields defined in AGENTS.md §Strategy Watchdog.

```bash
# Check first — NEVER create a duplicate
openclaw cron list --json | grep -q byreal-dca

# Register if not found
openclaw cron add \
  --name byreal-dca \
  --every 1h \
  --session isolated \
  --timeout-seconds 600 \
  --announce \
  --to <user_telegram_id> \
  --message "DCA executor. FIRST read the skill file at ~/.openclaw/workspace/skills/byreal-dca/SKILL.md — follow the 'Workflow: Daily Execution (Cron)' section exactly, including retry logic and exit monitoring. Read all ~/.openclaw/workspace/configs/dca/*.json. For each active plan: execute the full cron workflow from the skill. Report results."
```

---

## Workflow: Daily Execution (Cron)

For each active config in `~/.openclaw/workspace/configs/dca/*.json`:

```
 1. Check if due        → skip if already executed today (or < interval)
 2. Check budget        → remaining_usdc ≤ 0 → if holdings > 0 set `holding_only`, otherwise go to Completion Flow
 3. Determine amount:
    Standard:   fixed amount_per_buy
    Defensive:  python3 {baseDir}/references/sma_check.py <TOKEN> --ma 200
                → above: 100% | below: 30%
    Aggressive: base × 1.2^step (cap at remaining, persist step in mode_params)
    Basic:      fixed amount_per_buy
 4. Get USDC for this buy:
    a. If idle_yield.position_id exists → ALWAYS withdraw from position:
       → byreal-cli --wallet-address <agent_wallet_address> positions decrease --nft-mint <position-addr> --amount-usd <buy_amount> -o json
       → Returns USDC + USDT proportionally. Swap USDT → USDC if needed.
       → position_id stays the same — no config update needed
       → If decrease fails → status=attention_required, STOP
       (Wallet USDC belongs to the user, not to the plan. Never spend it directly.)
    b. If no position → check wallet USDC balance:
       → wallet USDC ≥ buy amount → proceed to step 5
       → wallet USDC < buy amount → status=attention_required, STOP
 5. Gas check → wallet SOL < 0.01 → status=attention_required, STOP
 6. Dry-run quote
    → priceImpactPct > 1% → status=attention_required, STOP
    → route fails → log, skip, notify
 7. Record pre-buy token balance (byreal-cli --wallet-address <agent_wallet_address> wallet balance -o json)
 8. Execute swap (byreal-cli --wallet-address <agent_wallet_address> swap execute ... -o json)
 9. Check result:
    → balances / holdings changed as expected → SUCCESS, go to step 10
    → no observed state change OR swap error → RETRY FLOW:
      a. Wait 5 minutes
      b. Check token balance again
      c. Balance increased → buy actually landed, treat as SUCCESS
      d. Balance unchanged → safe to retry, execute swap again
      e. Retry also fails → record as missed, go to step 10 (failure path)
    ⚠ NEVER retry without the balance check — risk of double buy
10. If bbSOL enabled → SOL → bbSOL
11. Update config:
    Success:
    → execution_log: append buy record with txid
    → budget_tracking.remaining_usdc -= actual_buy_spend_usdc
    → budget_tracking.invested_usdc += actual_buy_spend_usdc
    → plan_state.consecutive_failures = 0
    → schedule.last_run_at = now
    Failure (step 9e):
    → execution_log: append record with action="missed", reason
    → plan_state.consecutive_failures += 1
    → if consecutive_failures ≥ 3 → status=attention_required
    → schedule.last_run_at = now
12. Check exit conditions (Smart DCA only — see Exit workflow)
13. Report: one line per token (see Response Formats: Daily Report)
```

No catch-up logic by default.

> **Why `--every 1h`?** The cron fires hourly so future sub-daily frequencies (e.g. every 4h) work without re-registering. For daily plans, step 1 skips if already executed today. If managing many active plans, be aware the 600s timeout leaves limited room for the 5-min retry wait — prefer deferring retries to the next cron run when multiple plans are active.

### Completion Flow

When `remaining_usdc <= 0`:

```
1. If holdings > 0:
   → set plan_state.status = holding_only
   → keep Smart Exit monitoring active
   → notify user: buy budget is exhausted, plan is now holding and monitoring exits
   → STOP
2. If idle_yield.position_id exists:
   → byreal-cli --wallet-address <agent_wallet_address> positions close --nft-mint <position-addr> -o json
   → swap returned USDT → USDC if needed
   → compare recovered idle funds vs budget remainder (= 0)
   → report difference as net idle yield / cash-management drift
   → set idle_yield.position_id = null
3. Set plan_state.status = completed
4. Set schedule.last_run_at = now
5. Notify user with final invested amount, holdings, and recovered idle funds
```

---

## Workflow: Management

| User says | Action |
|-----------|--------|
| "DCA status" | Read all configs, show state-first status report |
| "Pause DCA" | Set status=paused. Position stays earning yield. |
| "Resume DCA" | Set status=active. |
| "Cancel DCA" | Stop buying. Ask: (1) sell all now, (2) sell gradually, (3) keep holding. Close position when done. |
| "Add $500 more" | Increase total_budget and remaining_usdc. If position exists, `positions increase` to add funds. If plan is `holding_only` → set back to `active` (new budget means new buys). If plan is `paused` → keep paused, just update budget — user must explicitly resume. |
| "Make it $10/day" | Change amount_per_buy, recalculate duration, confirm. |
| "Switch to aggressive" | Recalculate reserve from `remaining_usdc` (not original budget). Clear old `mode_params`, populate aggressive params. Confirm with user showing new reserve and projected schedule. Switching back to standard is safe — just clear aggressive `mode_params`. Note: plans auto-enter Aggressive if USER.md `risk_tier` = `aggressive` — no manual switch needed. |
| "Run now" | Execute buy immediately (same as cron step 3-12). |
| "Skip today" | Log as skipped in execution_log. |

When answering status, lead with state → progress → next action → return.

---

## Workflow: Exit (Smart DCA Only)

Smart Exit **monitors** automatically but **always asks before selling**.

### Thresholds

Plan duration buckets are based on the planned schedule:
- `planned_days = ceil(total_budget / amount_per_buy)`
- Short plans (< 30 days) → use 1–3 mo bucket
- 1–3 mo = 30–89 days
- 3–6 mo = 90–179 days
- 6–12 mo = 180–364 days
- 12+ mo = 365+ days

When writing config, **always calculate `planned_days` first** and pick the matching bucket. Set `exit.tp_threshold`, `exit.ts_threshold`, `exit.dca_out_periods`, and `exit.trend_ma` from the table below.

| Plan Duration | Take Profit | Trailing Stop | DCA-out Days | Trend MA |
|--------------|------------|---------------|-------------|----------|
| < 30 days | +20% | -10% | 4–7 | 50 |
| 1–3 mo | +20% | -10% | 4–7 | 50 |
| 3–6 mo | +40% | -15% | 7–14 | 50 |
| 6–12 mo | +50% | -20% | 14–21 | 200 |
| 12+ mo | +100% | -25% | 21–28 | 200 |

### State Machine

```
inactive → return ≥ TP
  → "tracking" — notify user, record peak, NO sell

tracking → drawdown from peak ≥ TS
  → ASK user (see Response Formats: Exit Recommendation)
  → Approved → "selling" | Declined → stay in tracking

selling → each cron run:
  1. Trend check: python3 {baseDir}/references/sma_check.py <TOKEN> --ma <trend_ma>
     → price above trend MA → pause, notify
  2. Adaptive sell: (holdings / remaining_periods) × (price / avg_cost)
     bounded 0.5×–2.0× base amount
  3. If bbSOL → convert to SOL first
  4. Execute sell (swap token → USDC), `positions increase` to deposit proceeds

paused → trend reverts below MA → resume
       → paused longer than 2× DCA-out period → ask user whether to resume or force completion

completed → close position, final report
```

| User says | Action |
|-----------|--------|
| "Sell my SOL" | Show exit state, recommend one option |
| "Sell over N days" | Manual DCA-out with adaptive sizing + trend pause |
| "Turn off auto exit" | Set exit.mode=manual |
| "Emergency sell" | Full sell at market, require confirmation |


---

## Response Formats

See `references/response-formats.md` for all output templates (Plan Confirmation, Status Report, Daily Report, Exit Recommendation).

---

## Hard Constraints

1. Never claim success without txid proof — on-chain is the only source of truth for whether funds actually moved.
2. Track plan holdings from execution_log — never use raw wallet balance. `plan_holdings = sum(buys) - sum(sells)`. Wallet may hold tokens from other sources.
3. Failure → log, skip, notify. No blind retry outside the defined retry flow.
4. One LP position per plan — never open a second. If `positions open` succeeds but config save fails, detect existing position via `positions list` and recover.
5. Read config before writing — always load latest state before updating. Prevents stale-state overwrites if two cron runs overlap.

---

## Troubleshooting

| Error | Cause | Action |
|-------|-------|--------|
| `INSUFFICIENT_BALANCE` | Wallet USDC < buy amount and position decrease failed or no position exists | Set attention_required, notify user to deposit USDC |
| Position decrease fails | Insufficient liquidity in position or on-chain error | Set attention_required, report state; position remains intact |
| priceImpactPct > 1% | Low liquidity | Skip this buy, retry next cycle |
| Route not found | No swap path on Byreal DEX | Log, skip, notify — do not retry |
| No observed post-trade state change | TX may have failed or remained ambiguous | Treat as failed, do not record |
| yfinance timeout | SMA data unavailable | Default to Standard mode |
| Config JSON parse error | Corrupted config file | Set attention_required, do not execute |
| Position open fails | Stable pool issue or insufficient funds | Keep plan active with funds in wallet, report stable pool position setup failed |
| Duplicate cron | `openclaw cron list` shows existing byreal-dca | Skip registration, proceed normally |

---

## References

| File | Content | Load when |
|------|---------|-----------|
| `references/sma_check.py` | MA market check script with ticker mapping | Creating plan or cron needs mode check |
| `references/config-schema.md` | Full plan config JSON schema | Creating or updating plan config |
| `references/bbsol.md` | SOL→bbSOL conversion, accounting rules | SOL plan with bbSOL enabled |
| `references/whitelist-tokens.md` | Supported tokens with mint addresses and tickers | Token lookup, plan creation |
| `references/response-formats.md` | Output templates for all user-facing reports | Formatting status, confirmation, daily report, exit recommendation |

For full CLI documentation: `byreal-cli skill`.
