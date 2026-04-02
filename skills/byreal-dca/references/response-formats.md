# Response Formats

Templates for user-facing output. Use these as the baseline — adapt wording to context but keep the structure.

## Plan Confirmation

```text
DCA Plan for SOL
━━━━━━━━━━━━━━━━
Budget:     $1,000 USDC
Schedule:   $20/day × ~50 days
Mode:       Standard (price above SMA200)
Idle funds: Wallet or stable pool parking
Exit:       Smart Exit monitors, asks before any sell
First buy:  now

Confirm? (yes / adjust amount / change mode)
```

## Status Report

```text
SOL DCA — On Track
━━━━━━━━━━━━━━━━━━
Budget:    $200 / $1,000 invested (20%)
Holdings:  1.35 SOL (~$200.50)
Return:    +$0.50 (+0.25%)
Avg cost:  $148.15
Next buy:  $20 on Mar 26, 2026 10:00 UTC
Mode:      Standard
```

If `pending_action` or `last_error` exists, surface it first:
```text
SOL DCA — Needs Attention
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ Insufficient USDC — wallet and position both empty.
   Deposit USDC to continue.
```

## Daily Report (Cron)

```text
DCA Daily Report
━━━━━━━━━━━━━━━━
SOL: bought $20 → 0.133 SOL @ $150.20 | 10/50 buys | +1.2% return
BTC: skipped (price impact 1.8%) | 5/30 buys | -0.5% return
```

## Exit Recommendation

```text
SOL has dropped 22% from its recent peak ($185 → $144).

Recommendation: sell gradually over 14 days.

Options:
1. Approve gradual exit (recommended)
2. Keep holding
3. Sell all now at market
```

## Completion Report

```text
SOL DCA — Completed
━━━━━━━━━━━━━━━━━━━
Budget:    $1,000 invested over 50 days
Holdings:  6.75 SOL (~$1,012.50)
Avg cost:  $148.15
Return:    +$12.50 (+1.25%)
Idle yield recovered: $3.20 USDC
Status:    All buys complete. Smart Exit monitoring active.
```
