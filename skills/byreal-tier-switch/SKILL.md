---
name: byreal-tier-switch
version: 0.1.0
description: |
  Change risk tier / switch style / adjust risk level.
  Triggers: "换成激进模式", "switch to safe", "调整风险等级", "change my tier", "我想保守一点".
metadata:
  openclaw:
    emoji: "🔄"
---

# Skill: Byreal Tier Switch

> Change risk tier — reassemble SOUL.md, review open positions against new tier rules, update USER.md.
>
> **Depends on**: AGENTS.md §User Permission Model, §Session Startup.

User wants to change their risk tier (Safe / Balanced / Aggressive).

## Context

- Current tier is recorded in `USER.md` and baked into `SOUL.md`
- Tier files: `references/soul-safe.md`, `references/soul-balanced.md`, `references/soul-aggressive.md`
- Core identity: `references/soul-core.md`

## Flow

### 1. Confirm Intent

Show current tier vs requested tier. Brief difference summary — target range, stop-loss, communication style. Ask for confirmation.

Example:
> You're on Balanced right now. Aggressive means wider ranges, higher drawdown tolerance (up to 25%), and I'll auto-follow new opportunities. Sure you want to switch?

If they're vague ("I want less risk"), map it to a tier and confirm.

### 2. Reassemble SOUL.md

After confirmation, silently:
1. Read `references/soul-core.md` + target tier file
2. Concatenate core + tier content → overwrite `SOUL.md`

### 3. Position Review

- List all open positions with current parameters
- Highlight parameters that change under new tier (e.g. Balanced → Aggressive: stop_loss 15% → 25%, auto_rebalance off → on)
- Flag positions that violate new tier rules (e.g. switching to Safe but holding volatile LP)

### 4. User Decides

Don't auto-migrate anything. Offer concrete options per position:
- **Adjust** — modify parameters to fit new tier
- **Close** — exit the position
- **Keep as-is** — note the exception

Example:
> You've got an LP position in SOL/USDC with 15% stop-loss. Under Safe, that should be 5%. Want me to tighten it, close it, or leave it as an exception?

### 5. Update Records

- Update `USER.md` with new tier + timestamp
- Log the change in daily memory
