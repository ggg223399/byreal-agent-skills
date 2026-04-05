---
name: byreal-watchdog
version: 0.1.0
description: "Notification aggregator. Reads all strategy watchdog states, respects USER.md notification preferences, and delivers reports via the configured notification channel. Owns Daily/Weekly report delivery. Use when user wants to change notification frequency, format, or turn off routine pushes."
---

# Skill: Byreal Watchdog

> Notification aggregator and delivery layer. Decouples strategy execution from user-facing notifications.
>
> **Depends on**: AGENTS.md §Notification Routing, §Strategy Watchdog, §Report Schedule, §Platform Formatting.

## Overview

| Attribute | Value |
|-----------|-------|
| Category | Infrastructure — Notification |
| Risk | None — read-only with respect to strategy state; never executes trades or modifies positions |
| Complexity | ** Multi-step |

## Trigger Modes

1. **Cron** (primary): runs every `notify_interval`, performs a two-stage check before deciding whether to push
2. **User command**: user says "show me status" or "what's going on" — agent runs the watchdog aggregation immediately, bypassing cron timing

---

## Watchdog State

Location: `~/.openclaw/workspace/watchdog_state.json`

```json
{
  "pending_alerts": false,
  "notify_interval": "1h",
  "mute": false,
  "last_heartbeat": "<ISO 8601 timestamp>",
  "last_self_check": "<ISO 8601 timestamp>",
  "last_report_at": "<ISO 8601 timestamp>",
  "last_seen_alerts": {
    "<strategy_id>": {
      "alert_hash": "<hash>",
      "alerted_at": "<ISO 8601 timestamp>"
    }
  }
}
```

| Field | Writer | Purpose |
|-------|--------|---------|
| `pending_alerts` | Strategy crons (set `true`), watchdog (clear to `false`) | Stage 1 fast-path: if false, watchdog can skip reading individual strategy states |
| `notify_interval` | Watchdog (on register/update) | Strategy crons read this to compute 2x heartbeat timeout for degradation fallback |
| `mute` | Watchdog (on user request) | Suppresses routine pushes; alert fallback and 24h self-check still fire |
| `last_heartbeat` | Watchdog (every cycle) | Strategy crons check this for degradation detection |
| `last_self_check` | Watchdog | Tracks 24h self-check cadence |
| `last_report_at` | Watchdog | Tracks last push timestamp |
| `last_seen_alerts` | Watchdog | De-duplicates alerts — only push new/changed alerts |

All writes to this file must use atomic rename: write to `watchdog_state.json.tmp`, then `mv` to `watchdog_state.json`.

---

## Strategy Discovery

Watchdog uses **dual discovery** to find active strategies (union of both sources):

1. **`USER.md` Active Strategies table** — maintained by strategy skills at create/start/stop
2. **`configs/` directory scan** — fallback to catch strategies not yet reflected in the table

| Strategy Type | State Location |
|---------------|---------------|
| `byreal-dca` | `configs/dca/<TOKEN>.json` |
| `byreal-stable-yield-farm` | Strategy runtime state (contains watchdog fields) |
| `byreal-lp-copy-trading` | Strategy runtime state (contains watchdog fields) |

If both sources are empty, watchdog writes `last_heartbeat` and exits silently.

---

## Cron Registration

```bash
openclaw cron add \
  --name byreal-watchdog \
  --every <notify_interval> \
  --session isolated \
  --timeout-seconds 300 \
  --message "Watchdog quick check. Step 1: Read ONLY ~/.openclaw/workspace/watchdog_state.json and USER.md §Notification Channel. Step 2: Check pending_alerts flag and Notify On preference. If mute=true and pending_alerts=false → write last_heartbeat and end session. If errors_only and pending_alerts=false → write last_heartbeat and end. If summary_only and pending_alerts=false and not in report window → write last_heartbeat and end. If 24h since last_self_check → proceed to Step 3. If every_action → proceed to Step 3. Step 3 (only if push needed): NOW read the full skill at ~/.openclaw/workspace/skills/byreal-watchdog/SKILL.md, read all strategy states, compose and send notification per the skill's workflow."
```

### Frequency by Notification Preference

| Notify On | Default `notify_interval` | Rationale |
|-----------|--------------------------|-----------|
| `every_action` | `1h` (adjust at first register if shortest active strategy interval is < 1h) | Strategy-level changes don't need minute-level aggregation |
| `summary_only` | `1h` | Daily report time precision +/- 30 min |
| `errors_only` | `4h` | Pure fallback; strategy direct push is the primary path for errors |

---

## Cron Workflow

### Stage 1 — Quick Check (most cycles end here)

```
1. Read watchdog_state.json
     → mute, pending_alerts, last_seen_alerts, last_heartbeat, last_self_check

2. Read USER.md
     → Notify On preference, Report Schedule

3. Fast decision:
   - mute=true AND pending_alerts=false
       → write last_heartbeat → end session
   - errors_only AND pending_alerts=false
       → write last_heartbeat → end session
   - summary_only AND pending_alerts=false AND not in Report Schedule window
       → write last_heartbeat → end session
   - every_action
       → always proceed to Stage 2
   - 24h self-check due (now - last_self_check > 24h)
       → proceed to Stage 2 (even if mute)
```

### Stage 2 — Full Push (only when needed)

```
4. Read this SKILL.md for the full workflow

5. Discover active strategies:
     a. Read USER.md §Active Strategies table
     b. Scan configs/ directory
     c. Merge (union) both lists

6. Read each strategy's watchdog state fields:
     last_heartbeat, current_step, last_success_at, retry_count,
     strategy_id, strategy_name, status, budget_usd, current_value_usd,
     net_pnl_usd, net_pnl_percent, total_fees_earned_usd, total_costs_usd,
     days_active, last_report_at, alerts

7. Alert fallback check:
     FOR each strategy:
       Compare strategy.alerts against last_seen_alerts
       IF new or changed alert (hash mismatch):
         → Queue for push (even if mute — alerts cannot be suppressed by mute)
         → Update last_seen_alerts entry
       IF alert cleared:
         → Remove from last_seen_alerts

8. Routine push (skipped if mute):
     Apply effective notification preference per strategy:
       effective_pref = strategy.notify_on || USER.md global Notify On

     IF effective_pref == every_action:
       → Aggregate all strategy states into a single message, push
     IF effective_pref == summary_only:
       → Check if now falls within Report Schedule daily/weekly window
       → IF daily window: compose daily report (portfolio value, total PnL,
           per-strategy PnL + status + alerts, gas reserve)
       → IF weekly window: compose weekly report (adds 7-day trend,
           best/worst strategy, effective APY, recommendations)
       → Data sources: latest watchdog state (real-time) + memory/YYYY-MM-DD.md (execution history)
     IF effective_pref == errors_only:
       → Only push alerts (already handled in step 7)

9. 24h self-check:
     IF now - last_self_check > 24h:
       → Append to push message (or send standalone if nothing else to push):
         "Watchdog active, monitoring N strategies."
       → This fires even in mute mode
       → Update last_self_check

10. Format per AGENTS.md §Platform Formatting

11. Send via configured notification channel

12. Update watchdog_state.json (atomic write):
      last_heartbeat = now
      last_report_at = now (if push was sent)
      pending_alerts = false
      last_seen_alerts = updated map
```

---

## Notification Preferences

Read `USER.md` `Notify On` field:

| Notify On | Watchdog Behavior | Direct-Push Exceptions |
|-----------|-------------------|----------------------|
| `every_action` | Aggregate and push every cycle | Unaffected — always direct push |
| `summary_only` | Silent; push only during daily/weekly report windows | Unaffected — always direct push |
| `errors_only` | Silent; push only when alerts exist | Unaffected — always direct push |

### Per-Strategy Override

Each strategy's config or runtime state may contain a `notify_on` field that overrides the global preference:

```
effective_preference = strategy.notify_on || USER.md Notify On (global)
```

This allows configurations like "DCA errors only, LP every action" without additional token cost — strategy state is already loaded, the override is just one extra field check.

---

## Report Schedule Takeover

Watchdog fully owns delivery of Daily and Weekly reports defined in AGENTS.md §Report Schedule.

| Report | Previous Owner | New Owner |
|--------|---------------|-----------|
| Daily | No clear owner (scattered) | Watchdog cron |
| Weekly | No clear owner (scattered) | Watchdog cron |
| Instant (emergency) | Strategy skill direct push | Unchanged — strategy direct push with watchdog fallback |

Report Schedule becomes a configuration input to watchdog, not an independent push process. This prevents duplicate delivery.

### Daily Report Window

OpenClaw cron uses interval-based scheduling (`--every`), not wall-clock alignment. Watchdog checks whether the current time falls within the Report Schedule send window (e.g., user-configured 09:00 +/- 30 min). If it does, the daily report is composed and sent.

---

## Mute Mode

When user says "stop notifications" / "mute" / "quiet":

| | Mute Mode | Full Pause |
|---|----------|-----------|
| Watchdog cron runs | Yes | No |
| Routine pushes | Suppressed | Suppressed |
| Alert fallback check | Active (if strategy direct push failed, watchdog catches it) | Lost |
| 24h self-check | Fires (user gets at least one message per day) | Lost |
| Resume | "Resume notifications" / "unmute" | "Resume notifications" |

Mute state is stored in `watchdog_state.mute`. Even when muted, watchdog continues running so it can serve as the alert safety net.

---

## Self-Monitoring

- **Heartbeat**: every cycle, regardless of push outcome, writes `last_heartbeat` to `watchdog_state.json`
- **24h self-check**: once per 24h, sends a lightweight alive message to the user (e.g., appended to daily report or standalone: "Watchdog active, monitoring N strategies"). Fires even in mute mode.
- **External observability**: `last_heartbeat`, `last_report_at`, `last_self_check` are all in `watchdog_state.json` — an external supervisor (if deployed) can monitor these fields.
- **Strategy-side degradation**: strategy crons check `watchdog_state.last_heartbeat` after writing their own state. If `now - last_heartbeat > 2 * notify_interval`, the strategy degrades to direct push for that cycle. See AGENTS.md §Notification Routing for the full exception list.

---

## User Interaction

| User Says | Watchdog Action |
|-----------|----------------|
| "Stop notifications" / "Mute" | Set `mute = true`. Cron continues, alert fallback preserved. |
| "Resume notifications" / "Unmute" | Set `mute = false`. |
| "Push every 4 hours" | Update cron `--every 4h`, update `notify_interval` in state. |
| "Only send errors" | Update `USER.md` `Notify On` to `errors_only`, adjust cron frequency to `4h`. |
| "DCA errors only, LP every action" | Update per-strategy `notify_on` overrides in each strategy's config. |
| "Show me status now" | Immediately run Stage 2 aggregation + push. Does not change cron settings. |

---

## Token Consumption

OpenClaw cron runs LLM sessions — every watchdog cycle starts an LLM session regardless of outcome.

### Two-Stage Optimization

The cron `--message` inlines the Stage 1 decision rules so the LLM can exit early without loading the full skill file.

| Scenario | Files Read | Estimated Tokens |
|----------|-----------|-----------------|
| Idle (no push) | System prompt + short message + 1 JSON file | ~2k |
| Full push | System prompt + SKILL.md + USER.md + all strategy states + reasoning + output | ~6-8k |

### Daily Consumption Estimates

| Notify On | Watchdog Freq | Daily Cycles | Idle Tokens | Push Tokens | Daily Total |
|-----------|-------------|-------------|-------------|-------------|-------------|
| `every_action` | 1h | 24 | -- | ~6-8k x 24 | ~144-192k |
| `summary_only` | 1h | 24 | ~48k (mostly idle) | 1 daily report ~8k | ~56k |
| `errors_only` | 4h | 6 | ~12k | Occasional alert ~8k | ~12-20k |

Reference: strategy crons themselves consume ~240-480k tokens/day (DCA at 24 cycles x 10-20k each). Watchdog adds 5-40% of that depending on preference.

---

## Atomic Write Rules

All writes to `watchdog_state.json` follow the atomic rename pattern defined in AGENTS.md §Strategy Watchdog:

1. Write complete JSON to `watchdog_state.json.tmp`
2. `mv watchdog_state.json.tmp watchdog_state.json`

This prevents strategy crons from reading partial watchdog state during the write.
