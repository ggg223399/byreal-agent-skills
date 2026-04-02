---
name: byreal-idle-yield
version: 0.1.0
description: "Park idle USDC/SOL in lending protocols to earn yield between strategy deployments."
---

# Skill: Idle Yield

> Park idle USDC/SOL in lending protocols to earn yield while not deployed in LP strategies.
> Prevents capital from sitting at 0% APY between strategy deployments.
>
> **Depends on**: AGENTS.md §User Permission Model (new protocol = fresh confirmation), §Risk Limits.

## When to Use

- Wallet has >$50 USDC idle for >24h (not allocated to any strategy)
- User explicitly requests "earn yield on my idle funds"
- After emergency exit: funds sitting in wallet

## Supported Protocols

| Protocol | Asset | Type | Expected APY | Risk |
|----------|-------|------|-------------|------|
| Lulo (aggregator) | USDC, SOL | Best-rate lending | 5-15% | Low — auto-routes to highest yield |
| Marginfi | USDC, SOL | Lending | 5-12% | Low — audited, large TVL |
| Kamino Lend | USDC, SOL | Lending | 4-10% | Low — Kamino ecosystem |

> Protocol list is **not auto-expandable**. Adding a new protocol requires updating this file + user confirmation.

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `min_idle_usd` | number | `50` | `≥ 10` | Minimum idle balance to trigger |
| `min_idle_hours` | number | `24` | `≥ 1` | How long funds must be idle before deploying |
| `protocol` | enum | `lulo` | `lulo`, `marginfi`, `kamino` | Preferred protocol. Lulo auto-routes. |
| `reserve_usd` | number | `20` | `≥ 5` | Always keep this much liquid for gas + quick entry |
| `max_deposit_pct` | number | `90` | `1–100` | Max % of idle funds to deposit |
| `auto_withdraw_on_strategy` | bool | `true` | — | Auto-withdraw when a strategy needs capital |

## Runtime State

If this skill is active as a managed strategy sleeve, persist these watchdog fields in its runtime state so AGENTS.md §Strategy Watchdog can observe health:

- `last_heartbeat`
- `current_step`
- `last_success_at`
- `retry_count`

This skill does not require its own standalone cron by default. Re-evaluate it on session startup, after any strategy cycle that changes deployed capital, and after emergency exits or large balance changes.

## Decision Logic

```
0. GAS CHECK:
   IF wallet SOL < 0.01 SOL: SKIP + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"

1. CHECK IDLE:
   gas_reserve = 0.01 SOL  # AGENTS.md §Risk Limits minimum
   idle_balance = wallet_balance - deployed_in_strategies - gas_reserve - reserve_usd
   IF idle_balance < min_idle_usd: SKIP
   IF idle_since < min_idle_hours: SKIP

2. FIRST USE — require user confirmation:
   "You have ${idle_balance} USDC idle for {hours}h.
    Deposit into {protocol} for ~{apy}% APY?
    I'll keep ${reserve_usd} liquid. Auto-withdraw when needed for strategies.
    [Yes] [No] [Change protocol]"

3. DEPOSIT:
   deposit_amount = min(idle_balance * max_deposit_pct, idle_balance - reserve_usd)
   Execute deposit via protocol SDK
   RECORD: { protocol, amount, deposited_at, tx }

4. MONITOR (every strategy cycle):
   Check accrued yield
   IF a strategy needs capital AND auto_withdraw_on_strategy:
     Withdraw needed amount + buffer
     Wait for settlement
     Proceed with strategy deployment

5. WITHDRAW:
   On user request or strategy capital need
   Full withdrawal: claim yield + principal
   REPORT: "Withdrew ${amount} from {protocol}. Earned ${yield} ({days} days, {effective_apy}% APY)."
```

## API Reference

```typescript
// SAK (see TOOLS.md §Solana Agent Kit)
// Lulo (best-rate aggregator):
agent.lendAssets(amount)      // deposits to highest-yield protocol
agent.getBalance()            // check deposited + accrued

// Marginfi:
// Direct CPI via marginfi SDK — deposit, withdraw, check position

// Kamino Lend:
// Via Kamino SDK — supply, withdraw, check reserves
```

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Protocol hack / exploit | Very low | Only use audited protocols with >$10M TVL |
| Withdrawal delay | Low | Most Solana lending = instant withdrawal; verify before deposit |
| Opportunity cost | Medium | Auto-withdraw when strategy needs capital |
| Rate drops to 0 | Medium | Monitor APY; if <1% for 7d, withdraw and notify user |
