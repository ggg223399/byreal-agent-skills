---
name: byreal-trading-comp
description: "Use when the user wants to participate in, climb the rank on, or check their standing in a Byreal trading campaign — Byreal's recurring volume-based swap competitions that rank wallets by credited trading volume across a fixed set of eligible pools for one season. Trigger phrases include 'join the byreal trading campaign', 'enter the current byreal contest', 'boost my trading campaign rank', 'compete on the byreal trading campaign leaderboard', 'byreal swap competition', mentions of volume-ranked competitions on Byreal, references to volume farming on whichever pools the current Byreal campaign whitelists, or any Byreal volume-based leaderboard. Also use when the user asks to check their current rank, estimated reward, or trading volume in a Byreal campaign."
---

# Byreal Trading Competition

Generate competition-eligible swap volume by running Byreal-router round trips on whitelisted pools. Every cycle adds eligible trading volume but burns fees and price impact; make that tradeoff visible before and during execution.

Live swaps call `byreal-cli swap execute --confirm` through the Byreal router. Eligible campaign volume comes from the Byreal router. Use `agent-token` for read-only wallet resolution/balances and signing fallback.

## Load References

Use progressive disclosure:

- Rank-only request: follow the `Rank Check Flow` section below; no reference load needed.
- Participation, live execution, setup confirmation, failures, or cheapest-pool comparison: read `references/participation-runbook.md`.
- Volume accounting, leaderboard lag, scheduler state, or risk explanation: read `references/accounting-and-risk.md`.
- Campaign-specific rules come from `config/campaigns/<campaign_type>.json`, or from `BYREAL_CAMPAIGN_CONFIG_DIR` when RealClaw mounts a local JSON registry.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/validate-campaign-config.sh [--all \| --resolve-path <target> \| <campaign_type_or_json_path>]` | Validate campaign JSON before upload or execution; `--resolve-path` prints the absolute config path. Honors `BYREAL_CAMPAIGN_CONFIG_DIR`. |
| `scripts/list-campaigns.sh [--with-status]` | List local campaigns; `--with-status` also checks campaign windows through the API. |
| `scripts/fetch-campaign.sh <campaign_type>` | Fetch campaign start/end metadata. |
| `scripts/fetch-pools.sh --campaign <campaign_type>` | Resolve eligible mint pairs to live pool addresses, TVL, fee, volume, and price. |
| `scripts/plan-cycle.sh --pool <name> --campaign <type> --per-swap-usd N [--start-mint M]` | Choose start mint and convert USD size into start-mint units. |
| `scripts/evaluate-pool.sh --pool <name> --campaign <type> --per-swap-usd N --wallet W [--start-mint M] [threshold flags]` | Shared pool gate: TVL cap, dry-run, and single-swap guard decision. |
| `scripts/dry-run-cycle.sh --input-mint A --output-mint B --start-amount N --wallet W [--slippage-bps]` | Dry-run both swaps. Caller decides run/skip from thresholds. |
| `scripts/read-live-token-balance.sh --wallet W --mint M [--symbol SYMBOL] [--raw]` | Read the current wallet balance for the live input mint immediately before a live swap. |
| `scripts/requote-leg.sh ... [--require-finite-pi]` | Re-quote the return swap after the first swap; pass the first swap's actual output and original input. Live runners should require finite price impact. |
| `scripts/format-cycle-report.sh ...` | Deterministically format post-cycle transaction evidence, local volume, and local cost from actual executed amounts. |
| `scripts/check-wallet.sh --wallet W --campaign T --pools P1,P2 --per-swap-usd N --sol-balance N --token-balances JSON [--gas-floor 0.02] [--start-mint POOL=MINT]...` | Read-only wallet readiness and pre-swap analysis. |
| `scripts/check-token-accounts.sh --wallet W --mints M1,M2[,M3] [--rpc-url URL]` | Read-only SPL account/rent check for setup confirmation. |
| `scripts/fetch-rank.sh <campaign_type> <user_address>` | Fetch wallet rank, API credited trading volume, estimated reward; annotates `offLeaderboard` for sentinel rank 500. |
| `scripts/fetch-leaderboard.sh <campaign_type> [page] [pageSize]` | Fetch one leaderboard page for gaps and rank projections. |

Shared exit codes: `0` ok; `1` usage; `2` network retry once; `3` HTTP 4xx/campaign not live or not found; `4` HTTP 5xx retry with backoff; `5` parse or return-swap dry-run bug; `6` missing/invalid campaign config; `7` no safe USD price/start side, require explicit `--start-mint`.

## Modes

**Rank check** is a read-only report. Use it for "what's my rank", "estimated reward", "where am I on the leaderboard", or explicit "read-only" / "no swaps". Render rank, credited trading volume, estimated reward, and loaded leaderboard gaps. See `Rank Check Flow` below.

**Participation** is volume farming. Use it for "join/farm/climb/boost rank", for setup confirmation, and for live cycles. Before any live or setup step, read `references/participation-runbook.md`; read `references/accounting-and-risk.md` when showing costs, rank projections, watchdog status, or risk. User must explicitly approve before live swaps.

**Cheapest/best pool questions** are data-first comparisons. Run `fetch-pools.sh` and `evaluate-pool.sh` for candidate pools, then render TVL, fee, cap, dry-run cost, and gate decision. Phrase any winner conditionally.

## Rank Check Flow

Read-only: resolve campaign and wallet, fetch rank plus one leaderboard page, render standing, wait for user.

1. Resolve `campaign_type` — user-named, or `list-campaigns.sh --with-status` auto-select when exactly one entry is active (tell the user which via `display.title`); otherwise list and ask.
2. Resolve wallet: explicit param > `agent-token wallet-info` > ask.
3. `fetch-rank.sh <campaign_type> <user_address>`. On non-zero exit, surface the classification.
4. One leaderboard page:
   - On leaderboard: `fetch-leaderboard.sh <campaign_type> <page> 20` covering the user's rank.
   - Off leaderboard: `fetch-leaderboard.sh <campaign_type> 1 300` so the top-300 cutoff loads.
   - Fetch failure: render rank with available data.
5. If config has `rules.minimum_volume_usd`, append reward-eligibility context without overriding the API's `estimatedReward`.
6. A brief opt-in invitation to participate is allowed after the rank output.

On leaderboard at rank N:

```text
rank N, credited trading volume $X, estimated reward $Y.
up: $<gap_up> more volume to overtake rank N-1.
down: rank N+1 is $<gap_down> behind.
```

where `gap_up = leaderboard[N-1].creditedVolume - my.creditedVolume` and `gap_down = my.creditedVolume - leaderboard[N+1].creditedVolume`. For rank 1, render the down gap only. If the adjacent row is outside the loaded page, say `next-page row not loaded`.

Off leaderboard (`fetch-rank.sh` returns `offLeaderboard:true`):

```text
outside top 300, credited trading volume $X, estimated reward $Y.
~$<gap_to_300> more volume to enter top 300.
```

If the top-300 cutoff is not loaded, say `top-300 cutoff not loaded`. If credited volume is below the relevant `rules.minimum_volume_usd` tier, note that the rank may not be reward-eligible yet.

## Hand Off Or Refuse

Hand off LP-side points mining to `byreal-xstocks-points-mining`, one-off manual swaps to `byreal-swap`, and perpetual contract competitions to `byreal-perps-cli`.

Refuse when `validate-campaign-config.sh` cannot find/validate a local config, when the requested pool is not in `eligible_pools`, when the campaign window is not active, or when all selected pools are gated out.

## Campaign Config

V1 uses a local `*.json` registry only. Each season has one `<campaign_type>.json`; default location is `config/campaigns/`, with `BYREAL_CAMPAIGN_CONFIG_DIR` as an override for RealClaw-mounted local configs. Add a new JSON for a new season or corrected campaign type.

Before using or uploading config, run:

```bash
scripts/validate-campaign-config.sh <campaign_type_or_json_path>
```

Required fields:

- `campaign_type`: equals file basename and API `campaignType`.
- `eligible_pools[]`: `{name, mints: [mintA, mintB]}`. Mint pairs are matched order-insensitively; symbols are not trusted.
- `display`: `{title, summary, reward_pool_text, link}` for user-facing setup/rank context.
- `docs`: optional official URLs for provenance.
- `rules`: optional official rule snapshot. Use it for explanation/projection, but treat `fetch-rank.sh` and `fetch-leaderboard.sh` as the source of truth for credited trading volume and reward estimates.
- `notes`: optional internal text.

If official scoring rules are missing, assume both swaps count equally and no pair/token multiplier applies. If `rules.scoring.realclaw_volume_multiplier` exists, mention it only as projected RealClaw credit until a later `fetch-rank.sh` confirms.

## Parameters

| Param | Default | Notes |
|-------|---------|-------|
| `campaign_type` | auto-resolved | Resolve through `list-campaigns.sh --with-status`; must also exist in campaign API. |
| `pools` | required | Subset of local `eligible_pools`. If unset, show live pool menu first. |
| `per_swap_usd` | required | USD-equivalent size for each swap; `plan-cycle.sh` does the conversion. |
| `volume_target_usd` / `cycles_target` / `runtime_until` | required one of | Stop condition; collect before wallet readiness checks. |
| `max_loss_usd` | unset | Optional cumulative cost budget, set when the user explicitly gives a dollar amount such as `$100`. |
| `cycle_interval_sec` | `180` | Wait between the first and return swap, and between cycles; apply +/-30% jitter. |
| `slippage_bps` | `100` | Change only with explicit user approval. |
| `gas_floor_sol` | `0.02` | Stop if SOL falls below this. |

Gate threshold defaults:

| Param | Default | Meaning |
|-------|---------|---------|
| `max_per_leg_pi_pct` | `2.0` | Single-swap cost/impact guard. If the user gives a percent like `5%`, use it here. |
| `max_roundtrip_cost_pct` | unset | Advanced explicit override only; set from the user's explicit round-trip cost limit. |
| `min_pool_tvl_usd` | unset | Optional explicit thin-pool floor. Leave unset by default; size cap and single-swap guard handle normal pool protection. |
| `max_per_swap_pct_of_tvl` | `0.05` | Auto-cap single-swap size as a fraction of pool TVL. |

Snapshot all thresholds at setup. Runtime edits apply to future sessions.

## Execution Invariants

- Enter wallet readiness after `campaign_type`, selected `pools`, `per_swap_usd`, and exactly one stop condition are known.
- Default start mint is decided by `plan-cycle.sh`; if user only holds SOL, say SOL-USD1 can start from SOL only with an explicit `--start-mint` override.
- Show `check-wallet.sh` pre-swap actions and wait for user approval.
- At setup, run `evaluate-pool.sh` per selected pool. If every selected pool is `skip`, refuse. You may name the blocking threshold, but threshold relaxation is a separate user decision.
- Before live confirmation, run `check-token-accounts.sh` for runnable pools and separate swap/PI loss, one-time token-account rent, and first-run total.
- If first-run total exceeds user-supplied `max_loss_usd`, refuse instead of executing.
- With no user-supplied dollar cost budget, leave `max_loss_usd` unset and show estimated burn in the setup summary.
- Wait for explicit user "yes" after setup confirmation before any `--confirm`.
- `success:true` with `confirmed:false` is ambiguous. Poll signature/balances before treating a swap as settled or proceeding.
- Live swap input amounts must be checked against current wallet balances before each submit. For configured-size runners, keep the planned first-leg amount and use the observed post-first-swap balance delta for the return leg. Use the full current balance only when the user explicitly requested an all-balance/manual cycle. Never use a prior quote/output amount as the next live `--amount`; quote/output values are for accounting and display only.
- First-swap failure: log failure and return to the next cycle/pool decision. Return-swap failure after the first swap succeeds: alert that wallet is holding `other_mint`, retry once at current `slippage_bps`, then pause as `paused_holding_other_mint`.
- Slippage, thresholds, and pools change through explicit user instruction.
- After a successful cycle, report transaction evidence and local accounting first. Final credited volume/rank comes from a later rank poll (see `references/accounting-and-risk.md` for lag tolerance).
- For activity-quality or reward-eligibility questions, use the risk template in `references/accounting-and-risk.md`.

## Minimum Participation Flow

1. Resolve campaign with `list-campaigns.sh --with-status`; auto-select only when exactly one active campaign exists.
2. Validate local config; show display copy, eligible live pools, and rank baseline when wallet is known.
3. Collect required params before wallet checks.
4. Check wallet balances and pre-swap needs.
5. Check campaign window and live pool resolution.
6. Run setup dry-runs/gates, token-account rent check, baseline rank, optional user cost budget check, and optional rank projection.
7. Show one setup confirmation and wait for explicit approval.
8. Register the cycle runner and rank watchdog. Each cycle runner tick runs at most one complete cycle, persists state, and exits.

Detailed setup, cycle-loop, failure, shared-gate, accounting, scheduler, and risk rules live in the references linked above.
