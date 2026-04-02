---
name: byreal-token-consolidate
version: 0.1.0
description: "Consolidate scattered small token balances into USDC or SOL."
---

# Skill: Token Consolidate

> Consolidate scattered small token balances ("dust") into USDC or SOL.
> After LP exits, copy trading, and airdrops, wallets accumulate many small token positions.
> This skill sweeps them into a single usable asset.
>
> **Depends on**: AGENTS.md §User Permission Model, §Risk Limits (slippage), byreal-jupiter-swap skill for non-Byreal swaps, byreal-rent-reclaim skill for post-swap cleanup.

## When to Use

- User says "consolidate", "clean up", "sweep dust"
- Pre-strategy: need clean USDC balance before deploying
- Post emergency-exit: multiple tokens scattered
- Periodic maintenance (monthly or on request)

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `target_token` | string | `USDC` | `USDC` \| `SOL` | Consolidate into this token |
| `dust_threshold_usd` | number | `1.0` | > 0 | Balances below this are considered dust |
| `min_swap_usd` | number | `0.50` | > 0, ≤ `dust_threshold_usd` | Skip if value too small to justify gas |
| `skip_tokens` | string[] | `[]` | — | Tokens to never consolidate (user holds intentionally) |
| `include_staked` | bool | `false` | — | Include staked/lent positions (requires withdrawal first) |

## Decision Logic

```
0. GAS CHECK:
   IF wallet SOL < 0.01 SOL: SKIP + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"

1. SCAN WALLET:
   getTokenAccountsByOwner(wallet) → all SPL balances
   FOR each token account:
     Get balance + current price (Jupiter Price API or Byreal token price)
     Classify:
       - SKIP if mint in [USDC, USDT, target_token, skip_tokens]
       - SKIP if mint is active strategy position NFT
       - SKIP if value_usd < min_swap_usd (gas > value)
       - DUST if value_usd < dust_threshold_usd
       - CONSOLIDATE if value_usd >= dust_threshold_usd

2. PRESENT PLAN:
   "Found {n} tokens to consolidate into {target_token}:
    | Token | Balance | Value | Action |
    | BONK  | 50,000  | $0.80 | skip (< $1 gas threshold) |
    | wETH  | 0.003   | $5.40 | swap → USDC |
    | JLP   | 0.5     | $12   | swap → USDC |
    Total: ~${total_usd} → {target_token}
    Proceed? [Yes] [Edit skip list] [Cancel]"

3. EXECUTE (sequential, not parallel — avoid slippage stacking):
   Sort by value descending (largest first)
   FOR each token:
     TRY byreal-cli swap (if pair exists on Byreal)
     FALLBACK byreal-jupiter-swap skill (if not on Byreal)
     IF swap fails: log, continue to next (don't block on one token)
     SLEEP 2s between swaps (avoid rate limits)

4. CLEANUP:
   Run byreal-rent-reclaim skill on newly emptied accounts

5. REPORT:
   "Consolidated {n} tokens → {total_received} {target_token}
    Skipped: {skipped_count} (below threshold or in skip list)
    Failed: {failed_count} (see details)
    Gas spent: {gas_sol} SOL"
```

## Capabilities

Some tokens cannot be swapped due to:
- **No liquidity** — no Jupiter route exists
- **Frozen accounts** — token authority froze the account
- **Transfer hooks** — Token-2022 with custom transfer logic
- **LP tokens** — must be redeemed, not swapped (e.g. JLP, Raydium LP)

```
FOR each token:
  1. Check Jupiter Quote API for route → no route = SKIP + flag "no liquidity"
  2. Check token account state → frozen = SKIP + flag "frozen"
  3. Check if token is a known LP/receipt token → flag "redeem first"
  Report non-operable tokens separately so user knows what's stuck
```

## API Reference

```typescript
// Jupiter Price API (batch pricing)
GET https://price.jup.ag/v6/price?ids={mint1},{mint2},{mint3}

// SAK (see TOOLS.md §Solana Agent Kit)
agent.getBalance(mint)           // single token balance
agent.trade(outputMint, amount, inputMint, slippageBps)  // swap

// Token account enumeration:
connection.getTokenAccountsByOwner(wallet, { programId: TOKEN_PROGRAM_ID })
connection.getTokenAccountsByOwner(wallet, { programId: TOKEN_2022_PROGRAM_ID })
```

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Swap slippage on illiquid dust | Medium | Skip tokens with no Jupiter route |
| Gas exceeds dust value | Medium | min_swap_usd threshold |
| Accidentally sell user's hold | Low | skip_tokens list + user confirmation |
| Scam tokens in wallet | Medium | Never interact with unknown tokens that have transfer hooks |
