---
name: byreal-rent-reclaim
version: 0.1.0
description: "Close empty SPL token accounts to reclaim SOL rent deposits."
---

# Skill: Rent Reclaim

> Close empty SPL token accounts to reclaim SOL rent deposits.
> Each empty token account locks ~0.00203 SOL. Wallets accumulate these over time from swaps, LP exits, and airdrops.
>
> **Depends on**: AGENTS.md §Transaction Safety, §User Permission Model (withdrawal = fresh confirmation).

## When to Use

- Periodic maintenance (weekly or on user request)
- Wallet has >10 empty token accounts
- Gas reserve is low and SOL can be recovered from rent

## Capabilities

| Action | Description |
|--------|-------------|
| Scan | List all token accounts with zero balance |
| Close | Close empty accounts, reclaim SOL to wallet |
| Report | Show how much SOL was recovered |

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `keep_mints` | string[] | `USDC, USDT, wSOL` | — | Token accounts to never close even if empty |
| `batch_size` | number | `20` | `1–40` | Max accounts to close per transaction |
| `min_accounts` | number | `5` | `≥ 1` | Skip if fewer than this many empty accounts |

## Decision Logic

```
0. GAS CHECK:
   IF wallet SOL < 0.01 SOL: SKIP + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"

1. SCAN:
   getTokenAccountsByOwner(wallet) → all SPL token accounts
   Filter: balance == 0 AND not in active strategy positions

2. SAFETY:
   Never close accounts for tokens in:
     - Active LP positions (check nftMintAddress list)
     - Token whitelist (USER.md preferences)
     - USDC, USDT, SOL (always keep these accounts open)
   Show user: {count} empty accounts, ~{sol_amount} SOL reclaimable
   Require user confirmation before proceeding (AGENTS.md §User Permission Model)

3. EXECUTE:
   Batch closeAccount instructions (max 20 per tx to stay within CU limit)
   Sign via agent-token
   Submit

4. REPORT:
   "Closed {n} empty token accounts. Recovered {x} SOL (~${usd})."
```

## API Reference

```typescript
// SPL Token closeAccount instruction
import { createCloseAccountInstruction } from "@solana/spl-token";
// closeAccount(account, destination, owner)
// For Token-2022 accounts, use the Token-2022 program variant

// SAK (see TOOLS.md §Solana Agent Kit)
agent.closeEmptyTokenAccounts()
```

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Close account needed by active strategy | Low | Check against active position NFTs + strategy state |
| Token-2022 accounts | Medium | Handle separately (different close instruction via Token-2022 program) |
| Dust balance missed | Very low | Only close accounts with exactly 0 balance |
