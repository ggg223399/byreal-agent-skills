# Participation Runbook

Read this before setup confirmation, live execution, failure handling, or cost-effective pool comparison.

## Setup Flow

0. Interview and validation:
   - If `campaign_type` is missing, run `list-campaigns.sh --with-status`. Auto-select only when exactly one entry is active; immediately show `display.title`, `display.summary`, `reward_pool_text`, `fetch-pools.sh --campaign <type>`, and rank baseline when wallet is known.
   - If `validate-campaign-config.sh --resolve-path <campaign_type>` fails, ask for a local JSON campaign config.
   - If `pools` is empty, show the live pool dump and ask. Use pools from `eligible_pools`.
   - Ask for `per_swap_usd` if missing.
   - Ask for exactly one stop condition: `volume_target_usd`, `cycles_target`, or `runtime_until`.
   - Enter wallet readiness after campaign, pools, size, and stop condition are all known.

1. Wallet/gas/readiness:
   - Resolve wallet: explicit param > `agent-token wallet-info` > ask.
   - Fetch SOL and token balances.
   - Run `check-wallet.sh --wallet W --campaign T --pools P1,P2 --per-swap-usd N --sol-balance <sol> --token-balances <json> --gas-floor <gas_floor_sol>` plus repeated `--start-mint POOL=MINT` overrides only when user explicitly chose a non-default start side.
   - If blockers exist, show the blocker text.
   - If `pre_swap_actions` exist, surface each action verbatim and ask whether to pre-swap.
   - If user only holds SOL, be precise: default planning may prefer stable start, but SOL-USD1 can start from SOL with explicit `--start-mint SOL-USD1=So11111111111111111111111111111111111111112`.
   - On `check-wallet.sh` exit 7, require explicit `--start-mint` per affected pool and re-run.

2. Campaign window:
   - Run `fetch-campaign.sh <campaign_type>`.
   - Network/5xx: refuse with classification.
   - 4xx/API error: refuse as campaign not found.
   - Before start or after end: refuse with timing.

3. Pool discovery:
   - Run `fetch-pools.sh --campaign <campaign_type>`.
   - Treat `missing_pair:<key>` as delisted for this run.
   - Use live pool address; mints remain the source of truth.
   - At least one selected pair must resolve.

4. Setup confirmation:
   - Snapshot gate thresholds and user overrides into runtime state.
   - Run `evaluate-pool.sh` for each selected pool.
   - If every selected pool returns `decision:"skip"`, stop setup with the threshold reasons returned by the scripts.
   - Snapshot each runnable pool's `plan.start_usd_price`, `plan.other_usd_price`, and `effective_per_swap_usd`.
   - Build the union of runnable pools' `start_mint` and `other_mint`, excluding native SOL, then run `check-token-accounts.sh`.
   - Separate swap/price-impact loss, one-time token-account rent overhead, and first-run total.
   - If user supplied `max_loss_usd` and first-run total exceeds it, refuse.
   - Fetch baseline rank; continue if this feedback API fails.
   - With no user-supplied `max_loss_usd`, leave it unset.
   - Optional: project rank delta using `references/accounting-and-risk.md`.
   - Show one confirmation with campaign, rank, per-pool dry-runs/gates, stop conditions, thresholds, optional `max_loss_usd`, token-account status, and burn/volume projection. Use `first swap` and `return swap` labels for the two directions.
   - One cycle is exactly two swaps: `first swap` from `start_mint` to `other_mint`, then `return swap` from `other_mint` back to `start_mint`. Pre-swap actions are separate wallet setup actions and close-out swaps are separate user-directed actions.
   - If the user asked for setup preview / eval / no execution, end with "setup only; send a separate execution confirmation if you want to proceed." Otherwise wait for explicit yes.

## Shared Pool Gate

Use `evaluate-pool.sh` for setup and every cycle. It owns:

1. `plan-cycle.sh` for start mint, other mint, and units.
2. `pool.tvl * max_per_swap_pct_of_tvl` cap, with rerun when capped.
3. Optional TVL floor check only when `min_pool_tvl_usd` is explicitly supplied.
4. `dry-run-cycle.sh` through Byreal router only.
5. Single-swap cost/impact guard via `max_per_leg_pi_pct`, default `2.0`. If either swap lacks a valid, finite `priceImpactPct`, treat it as missing guard data and skip the pool. If the user gives a percent like `5%`, use it here.
6. Optional round-trip cost threshold applies when explicitly supplied.

Caller only renders `{decision, reason, capped, effective_per_swap_usd, cap_usd, plan, dry_run_result}` and decides whether to proceed.

## Cycle Runner Tick

Each scheduled runner tick handles one pool in round-robin order and exits after at most one completed cycle. Runtime state owns the next pool pointer, completed-cycle count, cumulative cost, and stop status.

5a. Pool gate:
   - Acquire the runtime state lock. If a previous runner still owns the lock, record `skipped_overlap` and exit this tick.
   - Read runtime `status`; active status proceeds, while completed/cancelling/cancelled status releases the lock and exits.
   - Refresh `fetch-pools.sh --campaign <campaign_type>` at the top of each cycle.
   - Run `evaluate-pool.sh`; `decision:"skip"` logs and moves to next pool.

5b. Execute the first swap:

Before building the live command, read both the current input-mint balance and the current other-mint baseline:

```bash
read-live-token-balance.sh --wallet <wallet> --mint <start_mint> --raw
read-live-token-balance.sh --wallet <wallet> --mint <other_mint> --raw
```

Use the live start-mint balance as the amount only when the run is spending the full available side or continuing an all-balance/manual cycle. For configured `per_swap_usd` runners, keep the planned amount, but verify the live balance is enough before submitting. Keep the other-mint baseline for return-leg delta calculation. Do not use a prior quote, dry-run `uiOutAmount`, or previous leg output as the live `--amount`.

```bash
byreal-cli swap execute \
  --input-mint <start_mint> --output-mint <other_mint> \
  --amount <per_swap_in_start_units> --slippage <slippage_bps> \
  --wallet-address <wallet> --confirm -o json
```

Record signature and the actual first-swap output amount from the CLI response. `success:true` with `confirmed:false` needs signature/balance polling. If balances moved, use actual balance delta.

5c. Wait `cycle_interval_sec * random(0.7..1.3)`. Minimum default gives about 126 seconds.

5d. Re-quote the return swap:

After the first swap settles, read the live `other_mint` balance. For configured `per_swap_usd` runners, return only the observed balance increase from this first swap: `return_input = other_mint_after_first_swap - other_mint_baseline_before_first_swap`. This keeps pre-existing wallet balances and prior-cycle dust from affecting the current cycle. Use the full live `other_mint` balance only when the user explicitly requested an all-balance/manual cycle. The first swap's CLI `uiOutAmount` is evidence for accounting, not authority for the next spend.

```bash
read-live-token-balance.sh --wallet <wallet> --mint <other_mint> --raw
```

```bash
requote-leg.sh --input-mint <other_mint> --output-mint <start_mint> \
  --first-swap-out-amount <return_input amount> \
  --first-swap-in-amount <first-swap input amount> \
  --wallet <wallet> --slippage-bps <slippage_bps> --require-finite-pi
```

Before executing the return swap, re-read runtime `status`. If status changed to completed/cancelling/cancelled, pause with current balances and write state.

If the return-swap re-quote fails, pause with the wallet holding `other_mint`, alert the user, and ask how to proceed. When `return_swap_priceImpactPct` exceeds `max_per_leg_pi_pct`, pause with the current return quote and ask how to proceed.
If `return_swap_priceImpactPct` is missing, null, invalid, or non-finite, pause with the current quote status and ask how to proceed.

5e. Execute the return swap with mints swapped and the computed `return_input` amount. Re-read `other_mint` immediately before the command if more than a few seconds elapsed since the re-quote, recompute the configured-size return input as `current_other_mint_balance - other_mint_baseline_before_first_swap`, and use full balance only for an explicit all-balance/manual cycle. `confirmed:false` needs balance polling. If the configured-size return attempt fails with an amount/balance error, recompute the delta once from current balance and retry once at current `slippage_bps`. If wallet still holds the current cycle's `other_mint` delta after that bounded retry, persist `status:paused_holding_other_mint`, remove the cycle runner schedule, alert with the held delta and total held balance, and ask for a user-approved recovery action. If it no longer holds it, account from observed balances.

5f. Report immediately after successful cycle:
   - Run `format-cycle-report.sh` with the setup price snapshot, both tx signatures, actual executed amounts, price impacts, confirmation status, and final balances.
   - Use the script's `first_swap` and `return_swap` objects for user-facing labels, directions, tx URLs, and actual input/output text.
   - Use the script's `local_accounting.cycle_volume_usd_text`, `cost_start_units_text`, `cost_usd_text`, and `cost_pct_text`.
   - Include final balances for start/other mints from the script output when available.
   - token-account rent overhead if created.

5g. Stop checks after every cycle:
   - volume target met;
   - cycle target met;
   - runtime reached;
   - campaign ended;
   - wallet SOL below gas floor;
   - three consecutive first-swap failures;
   - cumulative cost >= user-supplied `max_loss_usd`, when present.
   - If a stop condition is met, persist `status:completed`, remove the cycle runner schedule, release the lock, and leave the rank watchdog to do its final reconciliation poll.
   - If no stop condition is met, persist the next pool pointer, release the lock, and let the next scheduled tick run the next cycle.

## Swap Failure Policy

- First-swap failure: log, skip, and continue from the next cycle/pool decision.
- Ambiguous CLI result: poll; signature alone is not settlement evidence.
- Return-swap failure after a successful first swap: alert immediately that wallet is holding `other_mint`. Retry the return swap once at current `slippage_bps`; then pause as `paused_holding_other_mint` and wait for a user-approved recovery action.
- `insufficient funds`, Solana `custom program error: 0x1`, or token-program balance errors are amount/balance failures, not slippage failures. Re-read the live input-mint balance and retry once with the refreshed balance when the leg is an all-balance continuation. If the refreshed balance is zero or the second attempt returns the same balance error, pause and report the held balances instead of increasing slippage.
- Slippage changes require explicit user approval.
