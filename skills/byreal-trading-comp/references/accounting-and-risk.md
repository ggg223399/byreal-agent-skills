# Accounting And Risk

Use this reference when showing projected burn, rank delta, cycle accounting, runtime state, or risk.

## Score And Rank API

Contest API base: `https://api2.byreal.io/byreal/api/dex/v2/contest`.

- `fetch-campaign.sh` wraps `GET /campaign/info`.
- `fetch-rank.sh` wraps `GET /rank/my`.
- `fetch-leaderboard.sh` wraps `GET /rank/list`.

Rank APIs are read-only feedback. They support setup context and later reconciliation. User-facing reports use `credited trading volume` for API-confirmed values and `volume` for local/projection values.

## Rank Projection

For setup-confirm rank projection, call `fetch-leaderboard.sh <campaign_type>` for the page covering the user's current rank. If the row one rank ahead is loaded:

Use the API volume field internally, then render it as credited trading volume:

```text
volume_gap = leaderboard[i-1].creditedVolume - my.creditedVolume
hours_to_gain_one_rank = volume_gap / projected_credited_volume_per_hour
```

If the user is off leaderboard or the page does not cover the adjacent row, skip projection.

## Deterministic Cycle Accounting

After live execution, call `format-cycle-report.sh` with actual executed amounts and the setup price snapshot. Use the script output for local cost and volume.

The script owns this accounting:

```text
cost_start_units = first_swap.actual_input_amount - return_swap.actual_output_amount
cycle_cost_usd   = cost_start_units * start_usd_price
first_swap_usd   = first_swap.actual_input_amount * start_usd_price
return_swap_usd  = return_swap.actual_input_amount * other_usd_price
cycle_volume_usd = first_swap_usd + return_swap_usd
```

For setup projections before execution, use the same formula with dry-run amounts, but label it as estimated.

```text
format-cycle-report.sh \
  --pool SOL-USD1 \
  --start-symbol SOL --other-symbol USD1 \
  --start-mint <start_mint> --other-mint <other_mint> \
  --start-usd-price <snapshot_start_price> \
  --other-usd-price <snapshot_other_price> \
  --first-in <actual_start_in> --first-out <actual_other_out> \
  --first-pi-pct <price_impact_pct> --first-tx <signature> --first-confirmed true \
  --return-in <actual_other_in> --return-out <actual_start_out> \
  --return-pi-pct <price_impact_pct> --return-tx <signature> --return-confirmed true
```

If this run is actually executing through RealClaw and config has `rules.scoring.realclaw_volume_multiplier`, projected rank credit is:

```text
projected_rank_credit_usd = cycle_volume_usd * realclaw_volume_multiplier
```

Otherwise projected rank credit equals local cycle volume. Later `fetch-rank.sh` reconciliation is the confirmed credited-volume source.

## User Cost Limits

Cost limits are optional and user-supplied.

- If the user gives a dollar amount such as `$100`, store it as `max_loss_usd` and stop only when cumulative local cost reaches it.
- If the user gives a percent such as `5%`, treat it as a single-swap cost/impact guard by passing `--max-per-leg-pi-pct 5` to `evaluate-pool.sh`.
- If the user gives both, apply both.
- With no cost limit supplied, leave `max_loss_usd` unset and use the default `2.0%` single-swap guard.

Always show estimated burn from dry-runs and local accounting.

## API Lag And Reconciliation

Byreal's campaign database usually reflects credited trading volume within about 5 minutes; allow up to 15 minutes before treating missing credited volume as abnormal.

During the lag window, show local estimated volume and API credited volume side by side. The immediate post-cycle report is local; the later rank poll is confirmed API credit.

Persistent disagreement above about 5% after the 15-minute lag budget suggests local accounting mismatch, failed swap state, or pool removal. Alert with the local and API values side by side.

Completion reports are two-stage:

1. Immediate execution report: signatures, actual inputs/outputs, balances, local accounting.
2. Later leaderboard reconciliation: fresh `fetch-rank.sh` / leaderboard read after lag.

## Scheduler And Runtime State

Use two jobs per instance:

1. Cycle runner tick every `cycle_interval_sec * (1 +/- 0.3 jitter)`, running one complete cycle for one pool in round-robin order, then exiting.
2. Rank watchdog every 5 minutes, calling `fetch-rank.sh`, updating dashboard, and reconciling credited volume with up to 15 minutes of lag tolerance.

Cycle runner invariants:

- One runner tick executes at most one `first swap` plus one `return swap`.
- Persist `cycles_total`, per-pool accounting, cumulative cost, and next pool immediately after each completed cycle.
- When `cycles_total >= cycles_target`, set status `completed` and remove the cycle runner schedule.
- Use a state lock. If another runner tick is active, record `skipped_overlap` and exit.
- Read `status` before the first swap and before the return swap. Status `cancelling`, `cancelled`, or `completed` pauses execution and exits after state/report update.
- Set runner timeout above worst-case one-cycle runtime, or keep the one-cycle body below the platform timeout. The default implementation should finish well under 300 seconds.

Runtime state should track:

```yaml
trading_comp_state:
  campaign_type: wlfi_season_1
  campaign: { name: ..., start_time_ms, end_time_ms }
  effective_thresholds:
    max_per_leg_pi_pct: 2.0
    max_roundtrip_cost_pct: null
    min_pool_tvl_usd: null
    max_per_swap_pct_of_tvl: 0.05
    max_loss_usd: null
    max_loss_usd_source: unset
    api_volume_lag_budget_min: 15
  pool_prices:
    WLFI-USDC:
      start_mint: <addr>
      start_usd_price: 1.0
      other_usd_price: 0.0668
  started_at: <iso>
  pools_active: [USD1-USDC, WLFI-USDC]
  pools_excluded_this_cycle: { SOL-USD1: "return_swap_pi=2.4 > max=2.0" }
  cumulative_volume_usd: <n>
  cumulative_cost_usd: <n>
  token_accounts:
    USD1ttGY1N17NEEHLmELoaybftRBUSErhqYiQzvEmuB:
      exists_at_setup: true
      created_during_run: false
      rent_lamports: 2039280
  unconfirmed_tx: null | { swap: first_or_return, signature: <sig>, first_seen_at: <iso> }
  running_cost_pct: <n>
  cycles_total: <int>
  cycles_skipped_gate: <int>
  per_pool:
    USD1-USDC: { volume_usd, cost_usd, cycles, last_dry_run: {...} }
  rank:
    last_polled_at: <iso>
    last_local_volume_change_at: <iso>
    rank_no: <int>
    off_leaderboard: <bool>
    credited_volume: <n>
    estimated_reward: <n>
    volume_reconcile_delta_pct: <n>
  stop_reason: null | max_loss_usd | volume_target | cycles_target | runtime_until | gas_floor | campaign_ended | router_unavailable | user
  recovery:
    status: null | paused_holding_other_mint
    held_mint: <addr>
    held_amount: <n>
    failed_return_swap_attempts: <int>
  lock:
    holder: null | <run_id>
    acquired_at: <iso>
  schedules:
    cycle_runner_id: <id>
    rank_watchdog_id: <id>
```

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Burn cost exceeds prize value | High by default | User-supplied `max_loss_usd` hard kill when present, plus setup-confirm burn/hour projection vs leaderboard gap |
| Tiny test dominated by token-account/rent overhead | Medium | Warn before very small live tests; budget setup SOL overhead separately |
| Thin pool blows up on sized swap | Medium | TVL sizing cap and single-swap PI gate |
| Pool moves between first and return swap | Medium | Return-swap re-quote and single-swap PI gate |
| Wallet stuck holding `other_mint` after return-swap failure | Low-Medium | Alert, one bounded retry, then user choice |
| USD1 depegs or WLFI rug-pulls mid-session | Low-Medium | Out of scope; skill trusts campaign pool list |
| Organizer reviews activity quality | Depends on rules | State that reward eligibility remains Byreal's decision |
| Byreal router unavailable | Low | No fallback; skip failures and stop after 3 consecutive first-swap failures |
| Slippage changes mid-run | Low | User approval required |

For activity-quality or reward-eligibility questions, read `rules.terms` or the linked official docs if present. Answer with the template below.

User-facing risk template:

```text
Reward eligibility remains subject to Byreal's final review and interpretation. This skill routes only through the configured eligible Byreal pools and reports local cost/credited-volume reconciliation, but reward distribution remains Byreal's decision. Jitter and pacing are for pool-health and execution stability.
```
