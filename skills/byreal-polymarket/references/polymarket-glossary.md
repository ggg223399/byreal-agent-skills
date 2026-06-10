# Polymarket Glossary

Use this reference when translating user wording into Byreal Polymarket CLI parameters.

## Core Objects

| Term | Meaning | CLI relevance |
| --- | --- | --- |
| Event | A grouped real-world question or topic, such as a match, election, or tournament group. | Search/list/detail starts at Event level. |
| Market | A tradable question inside an Event. One Event can contain many Markets. | A Market usually has a `conditionId`; use it for readiness, active-order filters, and cancellation filters. |
| Outcome | A tradable answer inside a Market, such as Yes, No, Team A, Draw, or Team B. | Must resolve to a CLOB outcome token before preview/order. |
| Outcome token | The CLOB asset representing one outcome. Also called `asset_id`, `token-id`, or a portfolio position id when returned as `positions[].position_id`. | `--token-id` is required for order preview/place. When selling an existing portfolio position, use that position's `position_id` as `--token-id` and carry its `condition_id` when returned. |
| Condition ID | Polymarket CTF market identifier for a Market. | CLI flags may call it `--condition-id` or `--market` depending on command. |
| Event ID | Polymarket/Byreal event identifier. | Required for `event detail`. |
| Order ID | CLOB order identifier for one submitted order. | Use for `order status` and exact `order cancel --order-id`. Do not confuse it with token id or condition id. |

## Market Types

| Term | Meaning | Common pitfall |
| --- | --- | --- |
| Binary market | A two-outcome Market, usually Yes/No. | Do not assume every Polymarket question is binary. |
| Multi-outcome market | A Market with more than two possible outcomes. | Resolve the exact outcome token from CLI output. |
| 3-way market | Sports moneyline-style outcome set: Team A / Draw / Team B. | Do not collapse this into Yes/No. |
| Moneyline | A sports winner market. | Often dominates sports volume; may be 2-way or 3-way depending on sport/rules. |
| Negative risk (`negRisk`) | Related markets that can be combined for risk reduction or arbitrage-like settlement mechanics. | Do not explain or trade related markets unless the user asks or the CLI returns them for the chosen Market. |

## Trading Terms

| Term | Meaning | CLI relevance |
| --- | --- | --- |
| Price | Probability-like tradable quote between 0 and 1. A price of 0.42 means about 42 cents per share, not a verified 42% fact. | Limit `--price` must satisfy `0 < price < 1`. Do not overstate prices as objective probabilities. |
| Bid | Highest visible price someone is willing to pay. | A SELL market order may fill against bid-side liquidity. |
| Ask | Lowest visible price someone is willing to sell for. | A BUY market order may fill against ask-side liquidity. |
| Mid | Midpoint between bid and ask. | Useful for display, but not guaranteed executable. |
| Last trade | Most recent matched trade price. | Can be stale or away from current bid/ask. |
| Current price | CLI-provided display price or snapshot price. | Treat as a snapshot label. If bid/ask/mid/last are available, name which one you are using. |
| Shares | Number of outcome tokens. | SELL market orders use `--size`; limit orders use `--size` for both sides. |
| Amount | USD/USDC budget for a BUY market order. | BUY market preview/place use `--amount`. |
| Selling an existing position | Selling owned outcome tokens for USDC and reducing exposure. | Use `--size`. Do not describe it as opening a short unless the CLI explicitly supports shorting; selling held YES shares gives up upside if YES wins. |
| Market order | Immediate order that takes available liquidity. | CLI uses FOK behavior for market orders. |
| Limit order | Resting order at a user price. | CLI uses GTC behavior; requires `--price` and `--size`. |
| FOK | Fill-or-kill: execute immediately or not at all. | Used for market orders. |
| GTC | Good-til-cancelled: rests until filled or cancelled. | Used for limit orders. |
| Slippage bps | Absolute price tolerance for market order execution. Default 100 means 0.01 price units. | CLI flag: `--slippage-bps`. |
| Preview snapshot | Read-only price/readiness snapshot used to guard execution freshness. | Pass via `--preview` when placing market orders if the CLI output provides it. |
| Preview expired | Market moved or snapshot became stale. | Rerun preview and ask for fresh confirmation. |

Binary YES/NO prices settle as complementary outcomes, but displayed quotes do not have to sum exactly to 1 at all times. Bid/ask spread, liquidity depth, last-trade timing, and snapshot differences can move displayed YES/NO values away from an exact sum. Do not invent a fee explanation unless the CLI output or a cited current source provides it.

## Accounts And Funding

| Term | Meaning | CLI relevance |
| --- | --- | --- |
| EVM EOA | User's EVM externally owned account. | CLI flag: `--evm-wallet-address`; defaults to RealClaw config when available. |
| Proxy wallet | Polymarket proxy/deposit wallet tied to the EVM account. | Must be READY for trading/funding paths. |
| Embedded Solana wallet | RealClaw Solana wallet used for Solana-side USDC deposits and withdrawals. | Funding commands resolve it from RealClaw config; do not pass an arbitrary recipient flag. |
| Polymarket available balance | Funds available for trading on Polymarket. | Read with funding balance or readiness commands. |
| Deposit | Move Solana USDC into Polymarket. | CLI command: `polymarket funding deposit --dry-run/--execute`. |
| Withdraw | Move Polymarket pUSD/proxy funds back to embedded Solana USDC. | CLI command: `polymarket funding withdraw --dry-run/--execute`. |
| Transfer status | Status of deposit/withdraw bridge operation. | CLI command: `polymarket funding status --type <deposit|withdraw>`. |

## Status And Visibility

| Term | Meaning | CLI relevance |
| --- | --- | --- |
| Whitelist | Byreal-visible Polymarket Events/Markets. | Empty search means no matching whitelisted event, not that the real-world topic does not exist. |
| Active/tradable | Market can currently accept orders. | Confirm before preview/order. |
| Closed/archived | Market/Event is no longer tradable or not visible. | Do not route new orders. |
| Accepting orders | Polymarket flag for order placement availability. | Treat false as non-tradable. |
| Liquidity | Available trading depth. | Use in user summaries and caution on thin markets. |
| Volume | Historical traded amount. | Useful for candidate ranking, not a guarantee of current liquidity. |
| Active order filters | Filters for listing or scoped cancellation of active orders. | `order active` can filter by `--market <conditionId>` and `--asset-id <tokenId>`. `order_id` is for status or exact cancellation, not for listing active orders. |
