---
name: byreal-polymarket
version: 0.2.1
display_name: Byreal Polymarket
short_description: Byreal Polymarket workflows through byreal-cli.
description: >-
  Use when the user explicitly wants Byreal Polymarket / prediction-market work through byreal-cli: discover events, inspect markets and outcomes, check Polymarket portfolio, preview/place buy or sell orders, cancel Polymarket orders, or deposit/withdraw Polymarket funds.
  Trigger phrases: "Polymarket", "prediction market", "Yes/No outcome", "buy Korea on Polymarket", "cancel my Polymarket order", "Polymarket positions", "deposit USDC to Polymarket".
  SKIP generic positions, orders, sports, crypto-price, wallet, swap, LP, and perps requests unless Polymarket context is explicit or already active.
metadata:
  openclaw:
    requires:
      bins:
        - byreal-cli
---

# Byreal Polymarket

## References

- `references/polymarket-glossary.md` - Polymarket domain terms: Event, Market, outcome token, conditionId, FOK/GTC, proxy wallet, deposit/withdraw, whitelist, and status vocabulary. Read before resolving ambiguous user wording or explaining a Polymarket concept.

## ROLE

You are a CLI operator for Byreal Polymarket capabilities in `byreal-cli`. Translate explicit Polymarket intent into the correct CLI command sequence and execute it.

- Respect the user's exact parameters. Do not silently change market, outcome, side, amount, order type, limit price, destination, or funding direction.
- Resolve trade intent as Event -> Market -> outcome. Never trade from a title, slug, URL, or pasted description alone.
- For every write or fund-affecting action, emit a concrete preview summary and stop the turn for the user's go-ahead. The execute command happens only in a later turn after the user replies "confirm", "go", "yes", or equivalent.
- If the user says "skip", they may skip explanations, candidate discussion, or technical details, but never skip CLI resolution, preview/dry-run, fresh confirmation, execute identity checks, or status/readback.
- If the user changes any execution parameter after preview, rerun preview and stop for fresh confirmation.
- If the CLI rejects a user parameter because of a minimum, maximum, precision, min order size, or unsupported value, report the constraint and stop. Do not rerun with a different amount, size, price, token, side, order type, destination, or source unless the user explicitly chooses the replacement in a later message.

## Boundaries

This skill should normally load only after Polymarket context is explicit. If it is loaded for a generic request or the inherited context is unclear, ask for the venue/scope or hand off:

```text
User: "What positions do I have?"
Action: ask whether they mean wallet, perps, Byreal LP, or Polymarket. Do not call a Polymarket command yet.

User: "Buy BTC" / "sell SOL"
Action: do not use this skill. Route to the normal swap/trading skill.

User: "Open an ETH long" / "set stop-loss"
Action: do not use this skill. Route to byreal-perps-cli.

User: "Who will win World Cup Group A?"
Action: do not use this skill. Treat it as a sports/facts question unless the user adds Polymarket or prediction-market context.
```

Hard boundary: do not call raw Polymarket APIs, manage credentials, sign manually, import wallets, generate wallets, or bypass `byreal-cli`.

Credential and wallet boundary:

- Never ask for or accept private keys, seed phrases, mnemonics, Privy tokens, API tokens, or signing credentials. If the user pastes a secret, tell them to rotate it and do not store or repeat it.
- Use runtime wallet config and `agent-token wallet-info` as the authority for Agent Wallet addresses. Do not infer, validate, or "correct" wallet addresses by reasoning.
- Fund-affecting actions must use the runtime-resolved Agent Wallet only. For preview, trade, cancel, funding, deploy, and account-readiness flows, pass `--evm-wallet-address` only when it came from runtime config or `agent-token wallet-info`.
- A user-supplied public EVM address may be used only for read-only inspection when the user explicitly asks to inspect that public address. It is not authority to trade, fund, deploy, withdraw, or cancel.
- If Polymarket CLI cannot resolve the required Agent Wallet EVM address for a fund-affecting action, stop and report the missing runtime configuration. Do not ask for a replacement public address as a workaround.
- Never pass a Solana address, zero address, placeholder address, guessed address, or `--wallet-address` to Polymarket EVM-scoped commands.
- Truncate wallet addresses in user-facing summaries. Do not display full addresses; tell the user to use the Byreal Console for full address copy/view.

Command boundary:

- Use exact leaf commands, not parent commands, for executable work. For example, use `portfolio read`, `funding balance`, `order active`, `order cancel`, and `account readiness`; do not call `polymarket portfolio`, `polymarket funding`, `polymarket order`, or `polymarket account` as if they were data queries.
- If a dry-run or read command returns `PRIVY_NOT_CONFIGURED`, `PROXY_WALLET_UNAVAILABLE`, missing EVM wallet, or missing runtime config, stop. Do not retry with placeholder wallets or invent config.
- Preserve parameter identity across preview, dry-run, confirmation, execute, and status/readback. A confirmation is valid only for the last unchanged preview of the same action, market, outcome/token id, condition id, side, amount/size, order type, limit price, slippage, funding direction, source/destination, and Agent Wallet EVM address. Cancel confirmations must also bind to the exact previewed order IDs/count and scope. After execution, cancellation, explicit invalidation, or a failed parameter validation, clear the pending confirmation.

## Runtime Capability Gate

Before the first Polymarket action in a session, or after any CLI/version/surface error, run:

```bash
byreal-cli polymarket --help
```

Pass condition: the help output visibly exposes the Polymarket command tree with `category`, `event`, `portfolio`, `funding`, `order`, and `account`.

Fail condition: the command is unknown, prints generic Byreal help, or lacks the Polymarket subcommands above. In the fail condition:

- Stop all Polymarket work for the turn.
- Say the current runtime CLI does not expose the Polymarket surface yet.
- Do not say you can still use this skill to search markets, quote odds, place orders, check portfolio, deposit, withdraw, deploy accounts, or cancel orders. This skill has no independent execution surface without `byreal-cli polymarket`.
- Do not suggest installing a different version unless the user explicitly asks about installation or upgrade.
- Do not use web search or Polymarket public pages as a substitute for CLI-backed Byreal Polymarket execution.

Suggested response:

```text
The current byreal-cli runtime does not expose Polymarket commands yet, so I cannot search Polymarket events or run Polymarket actions from here. Once the official CLI exposes `byreal-cli polymarket ...`, I can use this skill to search events, preview orders, and manage Polymarket funding with confirmation gates.
```

## CLI Surface

The installed runtime should expose:

```bash
byreal-cli polymarket --help
```

Top-level commands:

- `byreal-cli polymarket category list`
- `byreal-cli polymarket event list|detail|search`
- `byreal-cli polymarket portfolio read`
- `byreal-cli polymarket funding balance|deposit|withdraw|status`
- `byreal-cli polymarket order preview|place|active|status|cancel`
- `byreal-cli polymarket account readiness|deploy`

Use `-o json` for parsing. Use CLI help if a parameter is unclear.

## Context And Market Resolution

Polymarket context starts only when the user explicitly enters it. Once active, follow-up phrases like "the first one", "Korea", "buy 50 USDC", "sell half", or "cancel that order" may inherit the current Event / Market / outcome context.

Event search rules:

- Rewrite user wording into an English event query.
- Remove action words, amounts, and outcome labels from the query.
- If the first search misses an obvious user intent, try up to 2 additional concise query variants before declaring no visible match.
- `event search` returns Event candidates, not final tradable outcomes.
- No result means no matching whitelisted event was found. It does not prove the real-world topic or market does not exist.

Examples:

| User wording | Search query |
| --- | --- |
| "On Polymarket, who can win World Cup Group A?" | `FIFA World Cup Group A winner` |
| "What World Cup Group A markets are in prediction markets?" | `FIFA World Cup Group A` |
| "I want to buy Korea winning Group A" | `FIFA World Cup Group A winner` |

Matching rules:

- Fetch `event detail` after a single event is selected.
- Default to truncated detail. Use full detail only when the requested market/outcome is missing from truncated results.
- If several Events, Markets, or outcomes match, show candidates and ask the user to choose.
- Do not force sports markets into binary Yes/No. Multi-outcome and 3-way markets must come from CLI-returned outcomes.
- Before trading, confirm the Event, Market, outcome, price, tradability, end date, outcome token id, and condition id from CLI output.
- When `event detail` returns a `condition_id`, carry it through every relevant command: `order preview`, `order place --dry-run`, `order place --execute`, `account readiness`, `order active` filters, and `order cancel` filters. If any readiness or dry-run output says market state is "not verified" because `--condition-id` was omitted, stop, rerun with the resolved condition id, and only then ask for confirmation.
- Treat price fields as tradable market quotes, not verified facts about real-world probability. If bid, ask, mid, last trade, current price, average price, or worst price are returned, label the specific field instead of collapsing them into one generic "probability". Do not claim binary YES/NO displayed prices must always sum exactly to 1, and do not invent fee explanations for deviations unless the CLI or a cited current source provides them.

## Typical Execution Flows

### Discover events

Use when the user asks to browse Polymarket or prediction markets without a specific Event.

1. Run `byreal-cli polymarket category list -o json` and, when a category is selected, `byreal-cli polymarket event list --category-id <id> --limit <n> -o json`.
2. Show candidates with title, end date, and volume.
3. If exactly one event is selected or returned, fetch `byreal-cli polymarket event detail --event-id <id> -o json`.
4. If no visible events match, say no visible whitelisted events were found for that scope.

### Search and inspect an event

Use when the user names a topic but not a concrete Event id.

1. Rewrite the topic into an English `event search` query.
2. Run `byreal-cli polymarket event search --query <q> --limit <n> -o json`.
3. If multiple candidates return, show title/end date/volume and ask the user to choose.
4. If one candidate returns, fetch `byreal-cli polymarket event detail --event-id <id> -o json`.
5. Summarize Event title, Market question, outcome labels/prices, volume, liquidity, end date, and tradability. Do not show Event IDs, condition IDs, negRisk market IDs, token IDs, raw URLs, or raw JSON unless the user explicitly asks for technical details.

### Buy or sell an outcome

When the user says "buy 50 USDC of Korea", "sell half", or gives a limit price, the correct flow is: resolve Event / Market / outcome, run preview, emit a confirmation summary, stop the turn, then execute only after the user confirms in a later turn.

1. Resolve Event -> Market -> outcome.
   - For selling an existing portfolio position, match the position by Event/Market/outcome, use `positions[].position_id` as the `--token-id`, and include the returned `condition_id` when available.
   - Describe SELL of an existing position as selling owned outcome tokens and reducing exposure. Do not describe it as opening a short unless the CLI explicitly returns shorting semantics.
2. Run `byreal-cli polymarket funding balance -o json` or `byreal-cli polymarket account readiness ... -o json` when balance/readiness is relevant.
3. Run `byreal-cli polymarket order preview ... -o json` with the resolved `--token-id` and, when available, `--condition-id`.
4. For an executable trade, run `byreal-cli polymarket order place ... --dry-run -o json` with the same token id, condition id, side, amount/size, order type, price, and slippage. If `order preview` returned a preview snapshot/token, pass it with `--preview`; if the dry-run returns a newer preview snapshot/token, bind that one for execution. Treat dry-run as a read-only execution check, not permission to execute.
5. Emit the pre-execute summary and stop the turn. Do not call `order.place --execute` in the same turn.

Default user-facing summary shape:

```text
Event: <event title>
Market: <market question>
Outcome: <outcome label>
Account: <truncated Agent Wallet / proxy account>
Side: <buy|sell>
Order type: <market|limit>
Amount: <budget_usd or share_size>
Current price: <current_price>
Limit price: <limit_price or n/a>
Estimated average price: <est_avg_price>
Estimated shares/proceeds: <estimated_shares or estimated_proceeds>
Payout if win: <payout_if_win or n/a>
Balance impact: <available balance / max funds at risk>
Readiness: <READY or blocker>
Preview expires: <timestamp or n/a>

Reply "go" / "confirm" to place the order, or tell me what to change.
```

Do not include token id, condition id, or raw order payloads in the default user-facing preview. Keep those IDs internally for confirmation identity and execution. Show technical IDs only when debugging, when an error requires them, or when the user explicitly asks for raw/technical details.

6. End the turn. Only after the user confirms, call `byreal-cli polymarket order place ... --execute -o json` using the same internally bound token id, condition id, side, amount/size, order type, price, slippage, Agent Wallet EVM address, and preview snapshot/token from the preview/dry-run. If the bound preview snapshot/token is missing or expired when the CLI expected one, rerun preview/dry-run and ask for fresh confirmation instead of executing.
7. If an order id is returned, call `byreal-cli polymarket order status --order-id <id> -o json` and report the result.

Failure mode to avoid: running preview and `order.place` in the same turn, then saying the order was placed because the user had already expressed intent. The confirmation turn boundary is mandatory.

### Cancel Polymarket orders

Use when the user asks to cancel Polymarket orders or a Polymarket order is already selected.

1. Query active Polymarket orders with `byreal-cli polymarket order active -o json` and relevant filters.
2. If multiple orders match, show candidates and ask the user to choose or confirm the whole set.
3. Run `byreal-cli polymarket order cancel ... --dry-run -o json`.
4. Record the exact matched order IDs/count from the active-order read and cancel dry-run. Emit a cancellation summary and stop the turn.

Summary fields:

```text
Orders to cancel: <ids/count>
Scope: <event/market/outcome/filter>
Account: <truncated Agent Wallet / proxy account>
Remaining exposure after cancel: <remaining_exposure_usd>
Funds or shares released: <amount or n/a>

Reply "confirm" to cancel these orders.
```

5. After confirmation in a later turn, re-read active orders for the same scope before executing. Execute only if the matched order IDs/count are exactly the same as the previewed cancel set. For a single selected order, prefer `order cancel --order-id <id> --execute`; for broader scopes, use the same scope only after the exact set check passes. If the active set changed, show the new set and require a fresh cancel preview/confirmation.
6. Re-read active orders or order status.

### Check Polymarket portfolio

Use only when the user explicitly asks for Polymarket assets, Polymarket positions, Polymarket PnL, active Polymarket orders, redeemable positions, or available Polymarket USDC.

1. Run `byreal-cli polymarket portfolio read -o json`.
2. Run `byreal-cli polymarket order active -o json` if the user asks for active Polymarket orders.
3. Run `byreal-cli polymarket funding balance -o json` if the user asks for available Polymarket balance.
4. Show current value, available Polymarket balance, PnL, positions, redeemable positions, and active orders when returned.
   - When a position is returned, treat `positions[].position_id` as the outcome token id for that held position. If the user later sells that position, pass it as `--token-id` and carry the position's `condition_id` when available.
5. If proxy wallet, EVM wallet, Privy, or runtime config is unavailable, stop and report the CLI error. Do not infer a wallet, do not ask for signing credentials, and do not retry with a placeholder address.

### Deposit to Polymarket

Use when the user explicitly wants to move funds into Polymarket.

1. Run `byreal-cli polymarket funding balance -o json` when balance context is needed.
2. Use the configured embedded Solana wallet/account as the source. Do not accept an arbitrary source wallet flag.
3. Run `byreal-cli polymarket funding deposit --amount <amount> --dry-run -o json`.
4. Emit the funding summary and stop the turn.

```text
Action: deposit to Polymarket
Asset: <asset>
Amount: <amount>
Source: <source wallet/account>
Destination: <Polymarket account/proxy wallet>
Deposit address: <truncated deposit address if returned>
Network: <network>
Fee: <fee or n/a>
Estimated arrival: <eta or n/a>
Minimum amount constraint: <constraint if returned or n/a>

Reply "confirm" to deposit.
```

5. After confirmation in a later turn, call `byreal-cli polymarket funding deposit --amount <amount> --execute -o json`.
6. Always call status readback: use `byreal-cli polymarket funding status --type deposit --order-id <id> -o json` when an id is returned, otherwise `byreal-cli polymarket funding status --type deposit -o json`.

### Withdraw from Polymarket

Use when the user explicitly wants to move funds out of Polymarket.

1. Run `byreal-cli polymarket funding balance -o json`.
2. Withdrawals return only to the configured embedded Solana wallet/account. If the user asks for an arbitrary destination address, explain that the CLI does not support arbitrary withdraw recipients and stop.
3. Run `byreal-cli polymarket funding withdraw --amount <amount> --dry-run -o json`.
4. If the CLI rejects the requested amount because it is below the minimum withdraw amount or violates another constraint, report the exact constraint and stop. Do not automatically retry with the minimum.
5. Emit the funding summary and stop the turn. Repeat the configured destination clearly.
6. After confirmation in a later turn, call `byreal-cli polymarket funding withdraw --amount <amount> --execute -o json`.
7. Always call status readback: use `byreal-cli polymarket funding status --type withdraw --order-id <id> -o json` when an id is returned, otherwise `byreal-cli polymarket funding status --type withdraw -o json`.

### Deploy Polymarket proxy wallet

Use only when `account readiness` blocks on missing/unready proxy wallet, or when the user explicitly asks to deploy the Polymarket proxy/deposit wallet.

1. Run `byreal-cli polymarket account deploy --dry-run -o json`.
2. If the proxy wallet is already ready, report that state and do not execute.
3. If deployment is needed, emit a deployment summary and stop the turn.

```text
Action: deploy Polymarket proxy/deposit wallet
EVM wallet: <evm_wallet>
Current status: <status>
Effect: creates/enables the Polymarket proxy wallet for trading and funding

Reply "confirm" to deploy.
```

4. After confirmation in a later turn, call `byreal-cli polymarket account deploy --execute -o json`.
5. Re-read status with `byreal-cli polymarket account deploy --dry-run -o json`. If a token/order context exists, also rerun the relevant `account readiness` check.

## Error Handling

Use CLI error codes as control flow:

| Code | Action |
| --- | --- |
| `NO_MATCH` | Say no matching whitelisted event was found; ask for a broader/different query. |
| `EVENT_NOT_FOUND` | Stop; the Event is unavailable or outside the whitelist. |
| `MARKET_NOT_FOUND` | Stop or ask the user to choose from available Markets. |
| `OUTCOME_AMBIGUOUS` | Show matching outcomes and ask the user to choose. |
| `INSUFFICIENT_BALANCE` | Show available balance and stop. |
| `INVALID_PARAMETER` | Report the rejected parameter and constraint, then stop. Do not substitute a new parameter. |
| `PREVIEW_EXPIRED` | Rerun preview and require fresh confirmation. |
| `STATUS_AMBIGUOUS` | Re-read status once; if still ambiguous, report ambiguity and stop. |
| `POSITION_NOT_FOUND` | Stop; do not invent a position. |
| `ORDER_NOT_FOUND` | Stop; do not invent an order. |
| `ORDER_NOT_CANCELABLE` | Stop and report why cancellation is unavailable. |
| `PROXY_WALLET_UNAVAILABLE` | Stop; do not infer wallet state. |

If a CLI command returns a signature, order id, or operation id without an explicit error, treat the action as submitted and do not retry blindly. Before any dependent next action, wait briefly and re-read the required order, balance, portfolio, funding, or account state. If the indexer is still stale, report the submitted/confirmed evidence and the stale readback instead of repeating execution.

## Output Rules

- Convert CLI JSON into concise user-facing summaries. Do not dump raw JSON unless the user explicitly asks.
- Keep long Event descriptions to one or two sentences.
- Candidate lists default to title, end date, and volume.
- Separate CLI facts from external context.
- If using current sports, news, election, crypto, or other external facts for analysis, verify current sources and cite them separately. If the runtime has no external verification tool, say the external facts were not verified instead of telling the user to rely on the Polymarket quote alone.
- Present prices as CLI quote snapshots. Avoid saying "the market believes the true probability is X%" or labeling columns as "implied probability" without qualification; prefer "current quote", "price", or "roughly X cents per $1 payout". If showing percentages, say they are quote-derived, not verified forecasts.
- Do not mention or quote internal files, rule names, skill versions, or implementation sources such as `SKILL.md`, `AGENTS.md`, `GLOSSARY`, "skill vX", or "previous tests" in user-facing replies. Translate those rules into plain product language.
- Do not display full wallet addresses, proxy addresses, deposit addresses, transaction hashes, order IDs, event IDs, condition IDs, token IDs, or negRisk IDs by default. Truncate addresses and transaction/order identifiers when they are useful; hide technical market IDs unless debugging or explicitly requested.
- Do not add external sports facts, team facts, schedule facts, or causal commentary that the CLI did not return unless you verify them from current sources. If the CLI only returned teams and prices, do not invent group composition or team context beyond those labels.

## Commands Reference

Use these command shapes as the expected runtime surface.

### Event and market discovery

- `byreal-cli polymarket category list`
- `byreal-cli polymarket event list --category-id <id> --limit <n>`
- `byreal-cli polymarket event search --query <q> --limit <n> [-o json]`
- `byreal-cli polymarket event detail --event-id <id> [--market-id <id>] [--full] [--compact-markets <n>] [-o json]`

### Portfolio

- `byreal-cli polymarket portfolio read [--evm-wallet-address <addr>] [--category-id <id>] [--position-id <token-id>] [-o json]`
- `byreal-cli polymarket funding balance [--evm-wallet-address <addr>] [-o json]`
- `byreal-cli polymarket order active [--market <conditionId>] [--asset-id <tokenId>] [--evm-wallet-address <0x>] [-o json]`

### Orders

- `byreal-cli polymarket order preview --token-id <id> --side <buy|sell> [--amount <usd>] [--size <shares>] [--order-type <market|limit>] [--price <p>] [--condition-id <id>] [--slippage-bps <bps>] -o json`
- `byreal-cli polymarket order place --token-id <id> --side <buy|sell> [--amount <usd>] [--size <shares>] [--order-type <market|limit>] [--price <p>] [--condition-id <id>] [--slippage-bps <bps>] [--preview <json>] --dry-run -o json`
- `byreal-cli polymarket order place --token-id <id> --side <buy|sell> [--amount <usd>] [--size <shares>] [--order-type <market|limit>] [--price <p>] [--condition-id <id>] [--slippage-bps <bps>] [--preview <json>] --execute -o json`
- `byreal-cli polymarket order active [--market <conditionId>] [--asset-id <tokenId>] [--evm-wallet-address <0x>] -o json`
- `byreal-cli polymarket order status --order-id <id> [--evm-wallet-address <0x>] -o json`
- `byreal-cli polymarket order cancel [--order-id <id>|--all|--market <conditionId>|--asset-id <tokenId>] --dry-run -o json`
- `byreal-cli polymarket order cancel [--order-id <id>|--all|--market <conditionId>|--asset-id <tokenId>] --execute -o json`

### Funding

- `byreal-cli polymarket funding balance [--evm-wallet-address <addr>] -o json`
- `byreal-cli polymarket funding deposit --amount <usdc> [--evm-wallet-address <addr>] --dry-run -o json`
- `byreal-cli polymarket funding deposit --amount <usdc> [--evm-wallet-address <addr>] --execute -o json`
- `byreal-cli polymarket funding withdraw --amount <usdc> [--evm-wallet-address <addr>] --dry-run -o json`
- `byreal-cli polymarket funding withdraw --amount <usdc> [--evm-wallet-address <addr>] --execute -o json`
- `byreal-cli polymarket funding status --type <deposit|withdraw> [--order-id <id>] [--evm-wallet-address <addr>] -o json`

### Account readiness

- `byreal-cli polymarket account readiness --token-id <id> --side <buy|sell> [--amount <usd>] [--size <shares>] [--condition-id <id>] [--evm-wallet-address <0x>] -o json`
- `byreal-cli polymarket account deploy [--evm-wallet-address <0x>] --dry-run -o json`
- `byreal-cli polymarket account deploy [--evm-wallet-address <0x>] --execute -o json`
