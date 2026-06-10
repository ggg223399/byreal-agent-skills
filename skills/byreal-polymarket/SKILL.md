---
name: byreal-polymarket
version: 0.1.0
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

- Do not trigger on topic alone. Sports, elections, BTC, generic positions, and generic orders are not Polymarket requests unless the user explicitly says Polymarket / prediction market or the current conversation is already inside a Polymarket flow.
- Assume `byreal-cli` is preinstalled by the RealClaw runtime. Do not ask the user to install it. Your first action for any Polymarket task is exactly `byreal-cli polymarket --help`; do not substitute `byreal-cli --help`, `byreal-cli catalog`, `byreal-cli skill`, web search, or raw APIs for this runtime gate. If the command is missing or the help output does not show Polymarket subcommands such as `category`, `event`, `portfolio`, `funding`, `order`, and `account`, report that this runtime cannot run Polymarket actions yet and stop.
- Respect the user's exact parameters. Do not silently change market, outcome, side, amount, order type, limit price, destination, or funding direction.
- Resolve trade intent as Event -> Market -> outcome. Never trade from a title, slug, URL, or pasted description alone.
- For every fund-moving action, emit a concrete preview summary and stop the turn for the user's go-ahead. The execute command happens only in a later turn after the user replies "confirm", "go", "yes", or equivalent.
- If the user changes any execution parameter after preview, rerun preview and stop for fresh confirmation.

## Boundaries

This skill should normally load only after Polymarket context is explicit. If it is loaded for a generic request, stop and hand off:

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

Credential boundary:

- Never ask for or accept a private key, seed phrase, mnemonic, Privy token, API token, or signing credential.
- If an EVM wallet is missing, ask only for a public EVM address (`0x...`) or say the RealClaw runtime config must provide one.
- Do not offer to import or generate an EVM wallet inside this skill.
- Never pass a Solana address, a zero address, a placeholder address, or a guessed address to `--evm-wallet-address`.
- Do not use `--wallet-address` with `byreal-cli polymarket ...`; Polymarket EVM-scoped commands use `--evm-wallet-address` only.
- If the CLI defaults cannot resolve an EVM wallet, stop and report the missing runtime configuration.

Command boundary:

- Use exact leaf commands, not parent commands, for executable work. For example, use `portfolio read`, `funding balance`, `order active`, `order cancel`, and `account readiness`; do not call `polymarket portfolio`, `polymarket funding`, `polymarket order`, or `polymarket account` as if they were data queries.
- If a dry-run or read command returns `PRIVY_NOT_CONFIGURED`, `PROXY_WALLET_UNAVAILABLE`, missing EVM wallet, or missing runtime config, stop. Do not retry with placeholder wallets or invent config.

## Runtime Capability Gate

Before discovery, portfolio reads, funding, account, preview, order placement, or cancellation, run:

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

Checked from local `byreal-cli` help while preparing this skill. The installed runtime should expose:

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
- Before trading, confirm the Event, Market, outcome, price, tradability, and end date from CLI output.

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
5. Summarize Event title, Market question, outcome labels/prices, volume, liquidity, end date, and tradability.

### Buy or sell an outcome

When the user says "buy 50 USDC of Korea", "sell half", or gives a limit price, the correct flow is: resolve Event / Market / outcome, run preview, emit a confirmation summary, stop the turn, then execute only after the user confirms in a later turn.

1. Resolve Event -> Market -> outcome.
2. Run `byreal-cli polymarket funding balance -o json` or `byreal-cli polymarket account readiness ... -o json` when balance/readiness is relevant.
3. Run `byreal-cli polymarket order preview ... -o json`.
4. For an executable trade, run `byreal-cli polymarket order place ... --dry-run -o json` with the same token id, side, amount/size, order type, price, condition id, and slippage. Treat this as a read-only execution check, not permission to execute.
5. Emit the pre-execute summary and stop the turn. Do not call `order.place --execute` in the same turn.

Required summary shape:

```text
Event: <event title>
Market: <market question>
Outcome: <outcome label>
Side: <buy|sell>
Order type: <market|limit>
Amount: <budget_usd or share_size>
Current price: <current_price>
Limit price: <limit_price or n/a>
Estimated average price: <est_avg_price>
Estimated shares/proceeds: <estimated_shares or estimated_proceeds>
Payout if win: <payout_if_win or n/a>
Balance impact: <available balance / max funds at risk>

Reply "go" / "confirm" to place the order, or tell me what to change.
```

6. End the turn. Only after the user confirms, call `byreal-cli polymarket order place ... --execute -o json` using the same token id, side, amount/size, order type, price, condition id, and slippage shown in the summary.
7. If an order id is returned, call `byreal-cli polymarket order status --order-id <id> -o json` and report the result.

Failure mode to avoid: running preview and `order.place` in the same turn, then saying the order was placed because the user had already expressed intent. The confirmation turn boundary is mandatory.

### Cancel Polymarket orders

Use when the user asks to cancel Polymarket orders or a Polymarket order is already selected.

1. Query active Polymarket orders with `byreal-cli polymarket order active -o json` and relevant filters.
2. If multiple orders match, show candidates and ask the user to choose or confirm the whole set.
3. Run `byreal-cli polymarket order cancel ... --dry-run -o json`.
4. Emit a cancellation summary and stop the turn.

Summary fields:

```text
Orders to cancel: <ids/count>
Scope: <event/market/outcome/filter>
Remaining exposure after cancel: <remaining_exposure_usd>

Reply "confirm" to cancel these orders.
```

5. After confirmation in a later turn, call `byreal-cli polymarket order cancel ... --execute -o json`.
6. Re-read active orders or order status.

### Check Polymarket portfolio

Use only when the user explicitly asks for Polymarket assets, Polymarket positions, Polymarket PnL, active Polymarket orders, redeemable positions, or available Polymarket USDC.

1. Run `byreal-cli polymarket portfolio read -o json`.
2. Run `byreal-cli polymarket order active -o json` if the user asks for active Polymarket orders.
3. Run `byreal-cli polymarket funding balance -o json` if the user asks for available Polymarket balance.
4. Show current value, available Polymarket balance, PnL, positions, redeemable positions, and active orders when returned.
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
Network: <network>
Fee: <fee or n/a>
Estimated arrival: <eta or n/a>

Reply "confirm" to deposit.
```

5. After confirmation in a later turn, call `byreal-cli polymarket funding deposit --amount <amount> --execute -o json`.
6. Always call status readback: use `byreal-cli polymarket funding status --type deposit --order-id <id> -o json` when an id is returned, otherwise `byreal-cli polymarket funding status --type deposit -o json`.

### Withdraw from Polymarket

Use when the user explicitly wants to move funds out of Polymarket.

1. Run `byreal-cli polymarket funding balance -o json`.
2. Withdrawals return only to the configured embedded Solana wallet/account. If the user asks for an arbitrary destination address, explain that the CLI does not support arbitrary withdraw recipients and stop.
3. Run `byreal-cli polymarket funding withdraw --amount <amount> --dry-run -o json`.
4. Emit the funding summary and stop the turn. Repeat the configured destination clearly.
5. After confirmation in a later turn, call `byreal-cli polymarket funding withdraw --amount <amount> --execute -o json`.
6. Always call status readback: use `byreal-cli polymarket funding status --type withdraw --order-id <id> -o json` when an id is returned, otherwise `byreal-cli polymarket funding status --type withdraw -o json`.

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
| `PREVIEW_EXPIRED` | Rerun preview and require fresh confirmation. |
| `STATUS_AMBIGUOUS` | Re-read status once; if still ambiguous, report ambiguity and stop. |
| `POSITION_NOT_FOUND` | Stop; do not invent a position. |
| `ORDER_NOT_FOUND` | Stop; do not invent an order. |
| `ORDER_NOT_CANCELABLE` | Stop and report why cancellation is unavailable. |
| `PROXY_WALLET_UNAVAILABLE` | Stop; do not infer wallet state. |

If a CLI command returns a signature, order id, or operation id but the status is stale, follow `TOOLS.md` Post-Transaction Verification. Do not retry execution blindly.

## Output Rules

- Convert CLI JSON into concise user-facing summaries. Do not dump raw JSON unless the user explicitly asks.
- Keep long Event descriptions to one or two sentences.
- Candidate lists default to title, end date, and volume.
- Separate CLI facts from external context.
- If using current sports, news, election, or crypto facts for analysis, verify current sources and cite them separately.

## Commands Reference

These commands were checked from the local CLI help.

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
