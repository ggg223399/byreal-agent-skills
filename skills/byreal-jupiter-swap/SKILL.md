---
name: byreal-jupiter-swap
version: 0.1.0
description: "Execute token swaps outside Byreal pools via Jupiter v6 aggregator."
---

# Skill: Jupiter Swap

> Execute token swaps outside Byreal pools via Jupiter v6 aggregator.
> Byreal CLI only routes through Byreal CLMM pools. This skill covers everything else.
>
> **Depends on**: AGENTS.md §Risk Limits (slippage, price impact), §Transaction Safety, §User Permission Model (manual swap = fresh confirmation).

## When to Use

- User requests a swap for a pair **not available** on Byreal pools
- Strategy needs to convert a non-standard token (airdrop, reward) into USDC/SOL
- Pre-LP entry: user holds token X, needs token A + B for an LP position on a non-Byreal pool

## Capabilities

| Action | Description |
|--------|-------------|
| Quote | Get best route + expected output via Jupiter Quote API |
| Swap | Execute swap transaction with MEV protection |
| Limit Order | Place a limit order via Jupiter Limit Order program |
| DCA | Set up recurring swaps via Jupiter DCA program |

## Parameters

| Param | Type | Default | Constraints | Description |
|-------|------|---------|-------------|-------------|
| `input_mint` | string | — | — | Input token mint address |
| `output_mint` | string | — | — | Output token mint address |
| `amount` | number | — | `> 0` | Amount of input token (in human-readable units) |
| `slippage_bps` | number | `100` | `1–5000` | Slippage tolerance in basis points |
| `max_price_impact_pct` | number | `1.0` | `0.01–50.0` | Refuse if price impact exceeds this |
| `priority_fee` | string | `auto` | — | Priority fee in microlamports, or `auto` for dynamic estimation |

## Decision Logic

```
0. GAS CHECK:
   IF wallet SOL < 0.01 SOL: REFUSE + WARN "Gas reserve below minimum (AGENTS.md §Risk Limits)"

1. QUOTE:
   GET Jupiter Quote API → { route, outAmount, priceImpactPct, otherAmountThreshold }

2. SAFETY CHECKS (per AGENTS.md §Risk Limits):
   IF priceImpactPct > 1%: WARN user
   IF priceImpactPct > 5%: REFUSE unless user override
   IF amount > min($1000, 25% wallet NAV): require user confirmation
   Show: input amount, expected output, minimum received, price impact, route hops

3. CONFIRM:
   Manual swap → always require user confirmation (AGENTS.md §User Permission Model)
   Strategy-initiated swap → allowed within approved budget

4. EXECUTE:
   POST Jupiter Swap API → serialized transaction
   Sign via agent-token
   Submit to RPC with preflight checks
   Verify: check token balance after tx confirms

5. ON FAILURE:
   Retry 1x with 2x slippage
   If still fails: report error, do not retry
```

## API Reference

```
# Jupiter v6 Quote
GET https://quote-api.jup.ag/v6/quote
  ?inputMint={mint}&outputMint={mint}&amount={lamports}&slippageBps={bps}

# Jupiter v6 Swap
POST https://quote-api.jup.ag/v6/swap
  { quoteResponse, userPublicKey, wrapAndUnwrapSol: true, dynamicComputeUnitLimit: true }

# Jupiter Limit Order
Program: jupoNjAxXgZ4rjzxzPMP4oxduvQsQtZzyknqvzYNrNu

# Jupiter DCA
Program: DCA265Vj8a9CE2ism4IKPACbMhx86uiCqkvd2FaB5rmc

# SAK (see TOOLS.md §Solana Agent Kit)
agent.trade(outputMint, amount, inputMint, slippageBps)
agent.limitOrder(inputMint, outputMint, inAmount, outAmount)
```

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| MEV / sandwich | Medium | Jupiter MEV protection enabled by default |
| Price impact on low liquidity | Medium | Hard refuse >5%, warn >1% |
| Stale quote | Low | Quote valid ~30s, re-quote if execution delayed |
| Route through unsafe pools | Low | Jupiter handles routing; trust its liquidity sources |
