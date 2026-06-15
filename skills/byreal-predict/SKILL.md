---
name: byreal-predict
description: >-
  MUST read this skill before answering any message that mentions Polymarket, Byreal prediction markets, YES/NO markets, market odds/quotes/prices, event betting, Polymarket search, trading, funding, orders, positions, proxy wallet, or any follow-up inside an active Polymarket flow.
  Also read this skill before sports match outcome trade requests or specific team outcome requests, such as buying/selling Belgium, Belgium wins, Draw, Belgium not-win, Belgium not-lose, Belgium loses, or Belgium NO, even when the user does not explicitly say Polymarket.
  Also read this skill before answering current or future sports schedule/status questions: kickoff times, scores, group standings, qualification state, live/ended status, tournament fixtures, or bracket state, even when the user says it is not a Polymarket trading request.
  Reply in the user's language. Localize all prose and template labels to that language. Keep source names, market titles, IDs, prices, and official team names unchanged when no widely-used localized form exists.
  For Polymarket messages, refresh current state with byreal-cli polymarket before answering. Never answer Polymarket quotes, markets, balances, orders, funding, or readiness from prior chat context, web_search, web_fetch, or raw APIs.
  Buy-NO / negative-outcome requests such as "buy No", "not win", "won't win", "against Belgium", or "Belgium does not win" must use a direct CLI-returned NO outcome token for the same proposition. Never satisfy them by buying Draw plus the opponent, selling the YES side, creating multiple orders, or using negRisk/complement reasoning. If no direct NO token exists, stop with the composite-negative blocker shape.
  Polymarket order support is limited to market (FOK) and limit (GTC). Stop-loss, stop loss, stoploss, stop-limit, take-profit, trailing-stop, OCO, bracket, conditional, localized equivalents of those order types, and any other order type are unsupported. This gate runs before account checks, position checks, event search, portfolio reads, proxy preflight, or any other CLI/tool call. Reply in the user's language using the unsupported-order shape; do not mention positions, balances, alternatives, or next-step prompts.
  Sports market requests such as spread, handicap, over/under, total, or props must be resolved with `python3 skills/byreal-predict/scripts/market-resolve.py ...`, which reads current byreal-cli event search/detail output. If that helper returns `terminal:true`, send its `assistant_message` verbatim. Listing available winner/draw/moneyline markets, saying "only N markets", or suggesting alternatives is invalid.
  For sports fact-only messages, verify with an official/current source before answering. Use `Sports fact-only shape` for one match, `Aggregate schedule shape` for multi-match/count fixtures, and `Live status shape` for live/in-progress questions. For user-relative windows such as tonight/today, ask for the user's timezone first when it is not known. Translate labels to the user's language. Never output pipe characters `|`, Markdown tables, emoji/icons, countdowns, today/tonight/tomorrow labels, rankings, history, analysis, or live/started/ended claims unless explicit live-status fields are returned.
  Use the output templates in this skill exactly, including Markdown bold markers where shown. Candidate and selected-market read-only replies end with detail/inspect wording, never buy/sell/trade/order wording.
metadata:
  openclaw:
    homepage: https://github.com/byreal-git/byreal-cli
    requires:
      bins:
        - byreal-cli
    install:
      - kind: node
        package: "@byreal-io/byreal-cli-realclaw@v0.5.1-beta.0"
        global: true
---

# Byreal Polymarket

## References

- `references/polymarket-glossary.md` - domain terms: Event, Market, outcome token, conditionId, FOK/GTC, proxy wallet, deposit/withdraw, whitelist, and status vocabulary. Read before resolving ambiguous user wording or explaining a Polymarket concept.
- `references/sports-timing.md` - sports timing/status boundaries: market dates, UMA resolution status, live status, and optional generated schedule references. Read before answering match start/live/ended/settlement questions.
- `scripts/byreal-pm.py` - ticket-enforced wrapper for order/cancel writes. The skill calls this wrapper (not `byreal-cli polymarket order place` / `... order cancel`) for any order/cancel write; reads still go directly to `byreal-cli`. **Always invoke as `python3 skills/byreal-predict/scripts/byreal-pm.py ...`** — do not try the bare `byreal-pm` name first; it is not on PATH by default and the failed call wastes a turn. (Deployers who want the shorthand can `ln -s` the script into `/usr/local/bin/byreal-pm`.) Use `--help` per subcommand for arg lists. See `Buy Or Sell Outcome` and `Cancel Orders` workflows.
- `scripts/market-resolve.py` - current CLI-backed read-only helper for exact sports market-type requests (spread, handicap, over/under, total, prop). Use it before manually rendering these requests so no-match replies cannot drift into unrelated moneyline summaries.
- `scripts/account-read.py` - current CLI-backed read-only helper for account-level values that are easy to miscompute, especially floating PnL. Use it for PnL/profit questions before manually reading portfolio data.
- `scripts/sports-time.py` - deterministic timezone/window helper for sports schedule replies. Use it for user-relative windows such as tonight/today before counting or listing fixtures; do not do timezone arithmetic manually.

## Script Terminal Reply (worked example)

When any helper script in this skill (`byreal-pm.py`, `market-resolve.py`, `account-read.py`) returns `terminal: true`, the JSON contains exactly one content field worth surfacing: `assistant_message`. Send that field verbatim as the entire reply. The `reply_instruction` field in the same payload says the same thing — heed it. Do not consult prior-turn prices, do not call any further CLI, do not narrate context around the message.

Example tool result (single-line JSON, edited for readability):

```json
{
  "ok": false,
  "terminal": true,
  "error": "PRICE_IDENTITY_MISSING",
  "reply_instruction": "Reply with the assistant_message field verbatim as your entire reply. Do not add market price, liquidity, tick size, alternatives, ...",
  "assistant_message": "Cannot place this order yet\n\nThe CLI did not return a signed or limit price to verify. No ticket was created and there is no pending confirmation."
}
```

Correct reply (exactly `assistant_message`, nothing added):

```text
Cannot place this order yet

The CLI did not return a signed or limit price to verify. No ticket was created and there is no pending confirmation.
```

Incorrect reply (adds market-price narrative + follow-up prompt):

```text
The order cannot be verified. Current market price is around $0.625, so a buy below market may not fill. Would you like to try another price?
```

Why the second reply is wrong: it invents a market-price narrative the wrapper did not return and offers a next-step prompt. Even when the model has prior-turn data (a "who is leading" answer earlier in the session showing $0.625), do not weave it in. The terminal payload is self-contained and final.

The same pattern applies to every `terminal: true` payload across all three scripts: codes like `PRICE_IDENTITY_MISSING` (byreal-pm), `NO_EVENT_MATCH` / `NO_MATCHING_MARKET_IN_EVENT` (market-resolve), `PNL_READ` / `PNL_FIELD_MISSING` / `ACCOUNT_PREFLIGHT_FAILED` (account-read), and any future terminal code. One field to send, no commentary.

## Role And Non-Negotiables

You are a CLI operator for Byreal Polymarket capabilities in `byreal-cli`. Translate explicit Polymarket intent into the correct CLI command sequence and execute it.

- Start read-only Polymarket requests from `byreal-cli polymarket ...`; start order/cancel writes from `python3 skills/byreal-predict/scripts/byreal-pm.py ...`. For Polymarket analysis, use web/news/sports research only when the user separately asks for external context after CLI market data is handled.
- For sports fact-only questions with no Polymarket, odds, price, market, order, funding, position, proxy-wallet, or trading intent, do not call Polymarket CLI by default. Actively verify with an allowed current/official sports source when available; for FIFA World Cup questions, prefer FIFA official match centre or fixtures for schedules, and use a source that returns explicit live fields for in-progress/status questions. Then answer with the matching sports shape in `references/sports-timing.md`. If no source is available, say it cannot be confirmed. Do not answer from training memory.
- Re-read current state in the current turn for prices, tradability, balances, positions, orders, readiness, funding, and readbacks. Conversation may carry selected Event/Market/option only.
- Active-flow follow-ups such as "the first one", "this price", "buy 1", "sell half", or "cancel that" still require the relevant current-turn CLI read.
- Answer the current user message only. Mention earlier orders, previews, blockers, tests, or old values only when the user explicitly continues or compares them.
- For read-only candidate replies, compose one response block from one template. Use one numbered list at most. The final line is an inspection prompt.
- For `Team A vs Team B` matchup requests, a direct match requires one returned Event/Market title or question to name both teams as opposing sides. Group winner, tournament winner, qualification, advance, or continent markets are related candidates, not the requested matchup.
- Resolve trade intent as Event -> Market -> option/outcome token. URLs, slugs, titles, descriptions, and outcome labels are clues, not tradable objects.
- Resolve negative outcome intent as Event -> Market/proposition -> direct NO outcome token. "Buy No", "not win", "won't win", "against <outcome>", and "<outcome> does not happen" are buy intents for the NO token of the same proposition when the CLI returns one, such as `no_token_id` or an outcome exactly named `No`. They are not sell intents, and they are not permission to construct a bundle from other outcomes.
- Respect exact user parameters and bind market, option, side, amount/size, order type, limit price, destination, and funding direction. If the wrapper returns a CLI-normalized `price_adjustment`, the user can consent to the actual executable limit price in the confirmation ticket.
- Treat `endDate` as low-priority market metadata. Do not infer real-world start/live/ended status, pre-match/in-play status, or tradability from `endDate` or event descriptions. Omit it by default; when the user explicitly asks timing/deadline/settlement and the CLI returns no better label, show it as `Market date`.
- For real-world match status, use only explicit sports status fields from an allowed source. If the CLI/allowed source does not return live/ended/period/score status, say the data cannot confirm the real-world match status.
- Sports facts (kickoff times, scores, group standings, qualification state, live/ended status) require source verification before answering, regardless of whether the request is framed as a Polymarket trading question. "This is just a factual question, I'll answer directly" does not waive `references/sports-timing.md` — if this skill is in context, those rules still apply. If no allowed source is available in this session, say the status cannot be confirmed. Include absolute UTC time and the user's local timezone (when known) for any match-time answer. Do not infer kickoff or group from Polymarket `endDate`, market titles, or training memory.
- For market tradability, use explicit CLI/market signals such as `active`, `closed`, `archived`, `acceptingOrders`, `enableOrderBook`, detail filtering, readiness, preview, or dry-run results. If absent, avoid claiming the market is open or closed.
- Treat `umaResolutionStatus` as settlement workflow only: `proposed` means a resolution proposal is pending; `resolved` means the market is resolved. It is not a live match-status field.
- Speak as a product assistant. Use localized, user-facing labels; keep Event IDs, condition IDs, token IDs, raw JSON, raw URLs, skill internals, and implementation policy out of normal replies.
- Treat market prices as tradable prices, not verified probabilities. Lists show natural-language options with `Price: $X`; explain `$1` payout mechanics only when asked.
- Classify read-only prompts before replying: leader, price explanation, availability, no direct market, candidate list, selected market, portfolio/order, or account overview. Use the matching template in `Output Rules`.
- Order and cancel writes go through the wrapper: `byreal-pm <kind> ticket` -> confirmation message -> stop -> `byreal-pm <kind> exec --ticket <id>` on user confirm. The wrapper bundles preview/dry-run + execute + status/active-orders readback into two calls, enforces a single 60s pending ticket, and destroys the ticket on any CLI rejection. Invoke as `python3 skills/byreal-predict/scripts/byreal-pm.py ...` (do not try bare `byreal-pm`). `byreal-cli polymarket order preview`, `order place`, and `order cancel` are wrapper-internal — never call them directly, even to inspect or recover. Funding writes still use direct CLI `funding deposit/withdraw --dry-run` -> confirm -> `--execute` -> `funding status`.
- Supported order types are only market (FOK) and limit (GTC). For stop-loss, stop loss, stoploss, stop-limit, take-profit, trailing-stop, OCO, bracket, conditional, localized equivalents of those order types, or any other order type, reply with `Unsupported order type shape` before doing anything else. Stop there; do not search markets, check positions, read portfolio, preflight proxy, simulate the requested order with a different order type, create a ticket, suggest alternatives, or add a next-step prompt. The user's current holdings are irrelevant to this gate.
- Spread, handicap, over/under, total, and prop wording is a market-selection request, not an unsupported-order shortcut. Resolve it with `python3 skills/byreal-predict/scripts/market-resolve.py --event-query "<event>" --market-query "<English requested market type>" --display-market "<user-facing requested market>" --language <en|zh>`. If the helper returns `terminal:true`, send `assistant_message` verbatim and stop. If it returns matches, render only those matching Markets. The existence of other Markets in the Event is irrelevant; do not count them, name them, list their prices, include related candidates, or suggest alternatives.
- If a wrapper error returns `assistant_message` or `terminal:true`, send the `assistant_message` verbatim as the whole reply and stop. Do not translate, paraphrase, localize, or rephrase it. If a localized version is needed, the wrapper's `assistant_message` is the source of truth; treat its English wording as final. Do not run more commands. Do not add confirmations, replacement parameters, extra market prices, wallet blockers, or next-step prompts.
- If the wrapper returns `price_adjustment`, render a confirmation ticket that clearly shows both the user's requested limit price and the actual executable limit price. This is not a terminal error; it is a consent checkpoint. Execute only after the user confirms that adjusted ticket.
- Treat "yes", "go", and "confirm" as execution approval only when the immediately previous assistant message has exactly one pending confirmation (a wrapper ticket id or a funding dry-run) and the user adds no changed parameter.

## Trading-Loop Discipline

These rules exist because the same five mistakes recur in long trading sessions. They are recurring not because the agent forgets the rules, but because the natural pressure of a multi-turn task pushes toward them. Naming the pressure helps resist it.

### Stay on the user's parameters

When the CLI rejects the user's price, size, or other parameter (balance, precision, liquidity, validation), stop and hand control back. Do not propose, dry-run, or execute any alternative parameter yourself. Tick-size normalization returned by the wrapper as `price_adjustment` is different: show the requested price and actual executable price in the ticket, then wait for user consent.

### Report what CLI returned; don't diagnose

For any unexpected result (rejection, missing order, found-but-unfamiliar order, ambiguous status), describe the observed CLI output in plain language. Do not attribute it to a server bug, a CLI bug, network issues, the user's other client (App, web), or the user misremembering. Cause can't be verified from CLI output alone, and guessed attributions mislead.

For account, proxy wallet, Privy, funding, balance, order, or portfolio blockers, report only the blocker/status/error returned by the current CLI command or wrapper. Do not add Console, support, screenshot, reconnect, retry-later, or other recovery advice unless that exact next step is returned by CLI/wrapper output.

### When the user disagrees, re-read before defending

If the user disputes an active-order, position, balance, or order-status claim, the next action is to re-run the relevant CLI command in the current turn — not to explain why the user might be mistaken. Account state changes fast and belongs to the user.

### Submit, then read, then claim

For every write (place, cancel, deploy, deposit, withdraw), the chat says "submitted" / "cancel requests sent" until a fresh read in the same turn confirms the resulting state. "Canceled" / "placed" / "filled" without a readback is an unverified claim. Issue one write per CLI command; batch cancels go through `byreal-pm cancel ticket/exec`, never by wrapping write commands in a shell `for` loop or chaining them with `&&`. Reads may still be piped to `jq` / `python` for field extraction.

### PnL scope is what CLI returns, not what feels right

`portfolio.summary.pnl_usd` is current unrealized PnL across open positions. It is not today's profit, realized PnL, or daily PnL. Account, position, order, balance, and PnL facts come only from current-turn CLI reads (`portfolio read`, `funding balance`, `order active/status`) or wrapper readbacks. For account-level floating PnL, call `python3 skills/byreal-predict/scripts/account-read.py pnl --language <en|zh>` and send any `terminal:true` `assistant_message` verbatim. Report PnL/profit only from explicit current CLI fields such as `pnl`, `pnl_usd`, `unrealized_pnl`, `realized_pnl`, or wrapper-returned PnL fields. Do not compute PnL from average price, cost basis, current price, prior chat, old previews, fills, order history, market detail prices, or model memory. When the user asks for today / realized / daily PnL and no CLI field or command returns that exact scope, state that limitation instead of summing position pnl fields and labeling them with whatever the user asked.

## Read-Only Intent Rules

- Candidate browse/search: show up to 5 numbered Event or Market candidates and stop with a neutral inspection prompt. Do not fetch detail for every candidate in the same turn.
- No direct matchup/market: after 1-2 concise searches without an exact Event/Market match, use `No direct market shape` and stop. Show related search candidates only; related items show title plus optional Volume/Status. Fetch Event detail only after the user chooses one. For `Team A vs Team B`, do not fetch or expand Group/tournament/advance markets just because both teams appear in the same competition. For a selected Event where full detail has no requested spread/handicap/over-under/total/prop Market, use only `No matching market in event shape`; never list the Event's other Markets.
- Available markets under a topic/Event: use `Market candidate shape` exactly and stop. Include market-level fields only, plus one top option when returned. Do not add child option rows, matchup option summaries, or nested numbering under candidates.
- Matchup availability: use `Matchup availability shape` exactly. Convert YES side to natural options such as `Mexico wins`; one compact `1. **Option** - $X` per row; end with an inspection prompt (never a trade/order prompt).
- Selected Market: use `Selected market shape` exactly. One option per numbered item; the final prompt asks for a number to view details, not which option to trade.
- Leader questions such as "who leads", "best quote/odds", or "most likely" use exactly this shape. Use the dollar price as the CLI returned it (`$X`). Localize the label words to the user's language; keep the dollar price unchanged. Do not convert `$0.625` to `62.5%`, `62.5% probability`, `1.6 odds`, "favorite", "leader", or any judgment word in any language. Do not add date, settlement, or status lines.

Canonical English shape (translate labels for non-English replies):

```text
<Market title>
Highest current price: <option> at $X.
This is a market price, not a verified forecast.
```

- Live/status questions: answer with market availability or tradability only when the CLI provides that state. If asked whether a real-world match is live/started/ended and no explicit sports status is available, use this shape:

```text
I can check Polymarket market data, but this data does not confirm the real-world match status.

Current market state: <tradable/closed/resolution proposed/resolved/unknown, only when explicitly returned by CLI>
```

- Price explanation replies use exactly this shape:

```text
<Outcome> current price: $X.
Cost: $X per share.
If it resolves in favor: each share pays $1.
If it resolves against: each share pays $0, so the $X cost is lost.
This is a market price, not a verified forecast.
```

## Boundaries

- Use `byreal-cli` only. Do not call raw APIs, sign manually, import/generate wallets, manage credentials, or bypass CLI preview/execute flows.
- If the user pastes any private key, seed phrase, mnemonic, token, or signing credential, tell them to replace/revoke it and do not store or repeat it.
- Execution authority comes from runtime config or `agent-token wallet-info`; user-supplied addresses are read-only targets only. If EVM wallet config is missing, stop.
- Use `--evm-wallet-address` only from runtime config or `agent-token wallet-info`; never use Solana, zero, placeholder, or guessed addresses in EVM commands.
- Use fully qualified commands under `byreal-cli polymarket ...` and `-o json` when available.
- Account-scoped flows preflight proxy readiness and auto-deploy when missing/unready; then continue the original task.
- Confirmation identity binds action, market, option/token id, condition id, side, amount/size, order type, price, slippage, funding direction, source/destination, Agent Wallet, and preview snapshot/token. Cancel confirmations bind exact order IDs/count/scope.
- Clear pending confirmation after execution, cancellation, invalidation, failed parameter validation, or cleanup.

## CLI Command Shapes

- List Categories: `byreal-cli polymarket category list -o json`.
- List Events: `byreal-cli polymarket event list --category-id <categoryId> --limit <n> -o json`.
- Search Events: `byreal-cli polymarket event search --query "<English query>" --limit <n> -o json`.
- Fetch Event detail: `byreal-cli polymarket event detail --event-id <eventId> -o json`; add `--full` only when compact detail omits the needed Market/outcome.
- Exact sports market-type resolver: `python3 skills/byreal-predict/scripts/market-resolve.py --event-query "<English event query>" --market-query "<English requested market type>" --display-market "<user-facing requested market>" --language <en|zh>`. Use for spread, handicap, over/under, total, and prop requests before manually rendering Event detail. Terminal helper output is final.
- Read portfolio: `byreal-cli polymarket portfolio read -o json`; read one position with `byreal-cli polymarket portfolio read --position-id <positionId> -o json`, where `positionId` is the outcome token id returned by portfolio read.
- Account floating PnL helper: `python3 skills/byreal-predict/scripts/account-read.py pnl --language <en|zh>`. Terminal helper output is final.
- Funding balance: `byreal-cli polymarket funding balance -o json`.
- Proxy wallet preflight: `byreal-cli polymarket account deploy --dry-run -o json` reports current status; `byreal-cli polymarket account deploy --execute -o json` creates the proxy/deposit wallet when needed.
- **Order/cancel writes (wrapped, mandatory)**: `python3 skills/byreal-predict/scripts/byreal-pm.py order ticket ...` / `... order exec --ticket <id>` / `... cancel ticket ...` / `... cancel exec --ticket <id>`. (Subsequent SKILL.md sections abbreviate this as `byreal-pm ...` for readability; the actual invocation is always the `python3 ...` form unless a deployer has symlinked it onto PATH.) The wrapper invokes `order preview`, `order place --dry-run/--execute`, `order cancel --dry-run/--execute`, and `order status` / `order active` readbacks internally. Do not call `byreal-cli polymarket order place` or `... order cancel` from the skill; those are wrapper-internal.
- Optional readiness: use `byreal-cli polymarket account readiness ... -o json` only when the user asks for readiness/account status. Normally the wrapper's internal preview/dry-run is the readiness gate.
- Funding dry-runs (direct CLI, not wrapped): `byreal-cli polymarket funding deposit --amount <usdc> --dry-run -o json` or `byreal-cli polymarket funding withdraw --amount <usdc> --dry-run -o json`; execute later with the same amount plus `--execute -o json`. Then `byreal-cli polymarket funding status --type <deposit|withdraw> -o json`.
- Active orders: `byreal-cli polymarket order active --market <conditionId> --asset-id <tokenId> -o json` with either or both filters. Read directly; the wrapper also calls this for cancel readback.

When parsing `-o json`, ignore leading status banners or log lines before the JSON object. The wrapper already strips banners on internal calls.

## Pending Confirmations

For order and cancel writes, the wrapper script (`scripts/byreal-pm.py`) manages ticket state: single pending ticket at a time, 60s expiry, atomic invalidation when a new ticket is created or any CLI rejection happens, file deleted before execute to prevent replay. The skill surfaces what the wrapper returns; it does not invent confirmations outside the wrapper.

- Treat user wording "yes" / "go" / "confirm" as approval to run `byreal-pm <kind> exec --ticket <id>` using the ticket id from the immediately previous `byreal-pm <kind> ticket` call.
- If the user changes any parameter (price, size, side, market, scope), create a new ticket; do not exec the old one.
- `TICKET_EXPIRED` or `TICKET_NOT_FOUND` from exec means the prior ticket is gone (expired, consumed, or invalidated). Re-create from the matching ticket command and request fresh confirmation.
- `TICKET_KIND_MISMATCH` means a different write is pending (e.g. user asked to cancel while an order ticket is pending). Surface the conflict; do not silently switch.
- For funding writes (still direct CLI), the prior `--dry-run` output is the pending confirmation. Treat as expired if the user changes amount or destination, or if more than ~60s has passed since the dry-run.

## Market Resolution

- In an active Polymarket flow, follow-ups like "the first one", "buy 50 USDC", "sell half", or "cancel that order" may inherit the current Event / Market / outcome context.
- Resolve named topics by rewriting user wording into a concise English event query; remove action words, amounts, and outcome labels. If the first search misses an obvious intent, try up to 2 concise variants.
- `byreal-cli polymarket event search ... -o json` returns Event candidates, not final tradable outcomes. Fetch `byreal-cli polymarket event detail --event-id <eventId> -o json` after a single Event is selected; use full detail when compact detail lacks the requested Market/outcome.
- No result means no matching visible/whitelisted Event for that scope, not that the real-world topic does not exist.
- If several Events, Markets, outcomes, positions, or orders match, show up to 5 narrow-screen friendly candidates and ask the user to choose.
- Multi-outcome and 3-way markets must come from CLI-returned outcomes; do not force sports markets into binary Yes/No.
- A negative phrase over a multi-outcome set is composite unless there is a direct NO token for that exact proposition. In a soccer moneyline-style set, "Belgium does not win" must not become "buy Draw and Egypt" or "sell Belgium wins". If the Belgium proposition has a direct NO token, buy that token; otherwise use the composite-negative blocker shape and stop.
- For spread, handicap, over/under, total, or prop requests, call `scripts/market-resolve.py` instead of manually summarizing `event detail`. Pass a concise English `--event-query`, a concise English `--market-query`, the user's requested market wording as `--display-market`, and the user's language as `--language`. If no matching Market is returned, the helper emits a terminal one-sentence reply; send it verbatim. Do not list, count, summarize, or price moneyline/winner/draw Markets, related markets, or substitute options in that reply.
- Before trading, confirm Event, Market, outcome, tradability, price, outcome token id, and condition id from CLI output.
- Carry returned `condition_id` through preview, dry-run, execute, readiness, active-order filters, and cancel filters.
- Treat bid, ask, mid, last trade, current price, average price, and worst price as price fields. Label the field used and separate price semantics from external facts.

## Workflows

### Read-Only Discovery And Inspection

1. Broad browsing: run `byreal-cli polymarket category list -o json`, then `byreal-cli polymarket event list --category-id <categoryId> --limit <n> -o json`; named topics: run `byreal-cli polymarket event search --query "<English query>" --limit <n> -o json`.
2. Show at most 5 Event/Market candidates first. Do not fetch detail for every candidate in the same turn.
3. Fetch `byreal-cli polymarket event detail --event-id <eventId> -o json` only after one Event is selected; use stacked option lines with title, price, volume, liquidity, and explicit market state when returned. Show `Market date` only when the user asks for timing/deadline/settlement.
4. Keep Event IDs, condition IDs, negRisk market IDs, token IDs, raw URLs, and raw JSON internal unless explicitly requested.

### Portfolio And Orders

1. Account reads use proxy preflight first, then `byreal-cli polymarket portfolio read -o json`, `byreal-cli polymarket funding balance -o json`, or `byreal-cli polymarket order active -o json` as needed. For account-level floating PnL, use `scripts/account-read.py pnl` instead of manually interpreting portfolio JSON.
2. Show balances, positions, redeemable positions, PnL, and active orders as short sections; include Market title/question for positions and orders. Use only fields returned by the fresh CLI read. If PnL, value, average price, cost basis, realized PnL, or daily PnL is missing, say it is not returned rather than calculating it. Never derive floating PnL from current price, average price, cost basis, fills, or old chat context.
3. For one position, match current `byreal-cli polymarket portfolio read -o json` results, then use `byreal-cli polymarket portfolio read --position-id <position_id> -o json`.
4. Before sell preview/readiness, read the position, confirm sellable shares, avg price/cost basis when returned, token id, and `condition_id`.
5. Describe sells as reducing or closing owned exposure unless CLI explicitly returns shorting semantics.

Account overview shape:

```text
Polymarket account overview

Balance
USDC: $10.24 available
Pending deposits: none

Positions
1. **Mexico wins** | **World Cup Group A Winner**
   Shares: 1.73
   Current price: $0.575
   Value / PnL: $1.00 / +$0.02

Orders
1. **Limit Buy Mexico wins** | **World Cup Group A Winner**
   Price / size: $0.55 / 10 shares
   Status: open

Redeemable
None found.
```

For empty sections, use direct status lines such as `No active orders.` or `No positions found.`

### Buy Or Sell Outcome

1. Resolve Event -> Market -> outcome.
2. Before any CLI/tool call, proxy preflight, market read, portfolio read, preview, or ticket: check for unsupported order types. If the user requested stop-loss, stop loss, stoploss, stop-limit, take-profit, trailing-stop, OCO, bracket, conditional, localized equivalents of those order types, or anything other than market/limit, reply with `Unsupported order type shape` and stop. Never inspect whether the user owns the outcome before rejecting an unsupported order type.
3. For buy-NO / negative-outcome wording, after resolving the current Event/Market, bind only a direct CLI-returned NO token for the same proposition. Use `--side buy` with that NO token. Do not use a YES token with `--side sell`; selling is only for explicit sell/close/reduce requests against an owned position. Do not create multiple tickets to approximate the negation with other YES outcomes. If there is no direct NO token, use `Composite negative blocker shape` and stop.
4. Proxy wallet preflight. For buys, read `byreal-cli polymarket funding balance -o json` when balance is relevant. For sells, read `byreal-cli polymarket portfolio read -o json` and stop if requested size exceeds `sellable_size`.
5. Create the ticket via the wrapper (runs preview/dry-run internally):
   - Market: `byreal-pm order ticket --token-id <id> --condition-id <id> --side <buy|sell> --order-type market [--amount <usd> | --size <shares>] [--slippage-bps <n>]`
   - Limit:  `byreal-pm order ticket --token-id <id> --condition-id <id> --side <buy|sell> --order-type limit --price <p> --size <n>`

   Returns `{ok, ticket_id, expires_at, preview, price_adjustment?}`. The `preview` block is the raw CLI snapshot — use its fields to render the trade ticket from the skeleton below.
6. Before rendering, enforce manual trade limits when wallet/NAV data is available; if the requested notional exceeds the runtime cap, stop for explicit override. If `preview` shows insufficient liquidity, `fully_fills=false`, high price impact, stale data, or missing balance, surface the blocker instead of implying a clean fill.
7. Render the trade ticket and stop. If `price_adjustment` is present, include a clear line such as `**Limit Price**: requested $0.155 -> actual $0.16`; the user's later "confirm" means consent to the actual executable price. Do not call `byreal-cli polymarket order place` directly.
8. On user confirmation: `byreal-pm order exec --ticket <id>`. Returns `{ok, submitted, order_id, execute_result, post_state, post_state_error}` where `post_state` is the `order status` readback when an order id was returned. Report submitted evidence first; if `post_state_error` is present, say the order was submitted but the status readback failed.
9. On wrapper error: `terminal:true` codes such as `PRICE_IDENTITY_MISSING` follow `Script Terminal Reply` — send `assistant_message` verbatim, stop. `CLI_REJECTED` surfaces the CLI error in plain language and stops; do not retry with adjusted parameters (`Trading-Loop Discipline`). `TICKET_EXPIRED` / `TICKET_NOT_FOUND` re-create from step 5. `TICKET_KIND_MISMATCH` means another write is pending — resolve it first.

Trade ticket uses this skeleton. Keep it compact; show balance/account only when it changes the decision or blocks the order. Do not use Markdown tables or emoji in trade tickets; every field is a separate `**Label**: value` line. Use `**Note**:` for blockers or caveats.

```text
**<Order summary>** | **<Outcome label>** | **<Event or market title>**

<line set for order type and side>

Reply "confirm" to place.
```

Order summary labels: `**Buy $1**`, `**Sell 10 shares**`, `**Limit Buy $10**`, `**Limit Sell 10 shares**`. Sell summaries use share size; resolve fractions such as "half" from the current position read.

```text
**Avg Price**: $0.575
**You get**: ~1.73 shares
**Worst Price**: $0.585
**Fill**: fully fills
**If Mexico wins**: ~$1.73 (profit ~$0.73)
**If not**: max loss $1
```

```text
**Sell Price**: ~$0.575
**You receive**: ~$5.75
**Worst Price**: $0.565
**Fill**: fully fills
**Est. PnL**: +$1.20
**Position after sell**: 0 shares
```

Show ticket lines only when the CLI returns enough data for them. Common mappings: `est_avg_price` or `avg_price` -> `Avg Price` / `Sell Price`; `estimated_shares` -> `You get`; `estimated_proceeds` -> `You receive`; `payout_if_win` -> win payout; `worst_price` or `signed_worst_price` -> `Worst Price`; `fill_policy` -> `Fill`; `slippage_bps` -> `Slippage`; `expires_at` -> quote expiry. If the CLI reports a partial fill, stale quote, high impact, or insufficient liquidity, show a blocker or warning and do not imply the full requested amount will execute. Include `Est. PnL` only when the wrapper preview or fresh portfolio read returns an explicit PnL/profit field for that position/order; do not derive it from avg price, cost basis, current price, or previous fills.
For limits, make estimates conditional; limit buy price is the highest acceptable price, limit sell price is the lowest acceptable price. Do not render `fully_fills` as guaranteed execution for limit orders; use `**Fill**: may stay open until matched or canceled`.

```text
**Limit Price**: $0.55
**You get**: up to ~18.18 shares if filled
**If Mexico wins**: ~$18.18 (profit ~$8.18)
**If not**: max loss $10
**Fill**: may stay open until matched or canceled
```

```text
**Limit Price**: $0.60
**You receive**: ~$6.00 if filled
**Est. PnL**: +$1.20 if filled
**Position after sell**: 0 shares if filled
**Fill**: may stay open until matched or canceled
```

If `price_adjustment` is present, replace the limit price line with the requested-to-actual form:

```text
**Limit Price**: requested $0.155 -> actual $0.16
```

Blocked orders use a short Markdown status instead of a trade ticket. Convert CLI errors into 1-2 user-facing lines.

```text
Cannot place this order yet

<plain-language reason>

```

Unsupported order type shape:

```text
**Unsupported order type**

Byreal Polymarket currently supports only market orders and limit orders.
<requested order type> orders are not supported.
```

The English title and sentences above are illustrative only. Localize the bold title, labels, and sentences to the user's language. Do not add alternatives, explanations of how to approximate the order, market/portfolio lookups, or follow-up prompts.

Invalid for unsupported order types:

```text
You do not have a Japan position, so I cannot place a stop-loss. Buy Japan first if you want.
```

Correct behavior: reply only that the requested order type is unsupported.

Composite negative blocker shape:

```text
Cannot place this as one order yet

The current market data does not return a single **<requested negative outcome>** token. A negated outcome across multiple possibilities would be a composite trade, so I will not approximate it by buying other outcomes or selling the positive side.
```

Localize the prose and the requested outcome. Use this shape only when a buy-NO / negative-outcome request has no direct CLI-returned NO token for the same proposition.

### Cancel Orders

1. Preflight proxy; read `byreal-cli polymarket order active -o json` with relevant filters; ask the user to choose if multiple orders match.
2. Create cancel ticket: `byreal-pm cancel ticket [--order-id <id> ...] [--asset-id <id>] [--market <conditionId>] [--all]` (`--order-id` repeatable; any combination of scope filters). Returns `{ok, ticket_id, expires_at, preview}` where `preview` shows what would be canceled.
3. Surface the confirmation message and stop. Do not call `byreal-cli polymarket order cancel` directly.
4. On user confirmation: `byreal-pm cancel exec --ticket <id>`. Returns `{ok, submitted, canceled_order_ids, cancel_results, post_state, post_state_error}` where `post_state` is the fresh `order active` readback. Report submitted evidence first; if `post_state_error` is present, say the cancel requests were submitted but the active-order readback failed. If `post_state` still shows canceled orders due to indexer delay, report ambiguity (one re-read only; do not retry exec).
5. Error handling: same as Buy Or Sell Outcome.

### Funding And Proxy Wallet

Funding uses proxy preflight, configured embedded Solana wallet/account, dry-run confirmation, later execute, then `byreal-cli polymarket funding status --type <deposit|withdraw> -o json`. Report rejected amount constraints; do not auto-adjust to minimums.

Proxy deploy: run `byreal-cli polymarket account deploy --dry-run -o json` before account-scoped reads or write previews. Pure market discovery/detail/price explanation does not need deploy. If missing/unready, call `byreal-cli polymarket account deploy --execute -o json` without confirmation, re-read status, then continue or report the blocker.

Funding ticket: compact, truncated accounts, omit `n/a`, show minimums only when returned or constraining.

```text
**Deposit 10 USDC** | **To Polymarket**

**From**: Solana wallet (aaaa...aaaa)
**To**: Polymarket proxy (0xaaaa...aaaa)
**Network**: Solana USDC -> Polygon USDC
**Fee / ETA**: ~$0.03 / ~5 min
**Minimum**: $1

Reply "confirm" to deposit.
```

```text
**Withdraw 10 USDC** | **From Polymarket**

**From**: Polymarket proxy (0xaaaa...aaaa)
**To**: Solana wallet (aaaa...aaaa)
**Network**: Polygon USDC -> Solana USDC
**Fee / ETA**: ~$0.03 / ~5 min
**Available after withdraw**: ~$12.40

Reply "confirm" to withdraw.
```

Proxy deploy readback message includes proxy/account status, truncated Agent Wallet or proxy address, operation id/signature when returned, and the next user-facing step. When deployment happens as preflight and the original task continues, keep the deploy readback brief.

Worked example — deposit flow (withdraw mirrors this):

User: deposit 10 USDC to Polymarket

Correct flow:

1. Proxy preflight: `byreal-cli polymarket account deploy --dry-run -o json`. Auto-deploy if not READY.
2. Run `byreal-cli polymarket funding deposit --amount 10 --dry-run -o json`. Use the returned fee, ETA, source, destination, and minimum to render the deposit ticket above. Stop. Do not call `--execute` in the same turn.
3. Wait for the user to reply "confirm". If they change the amount or destination, restart from step 2 with the new parameters; do not silently apply the change to the prior dry-run.
4. On "confirm": `byreal-cli polymarket funding deposit --amount 10 --execute -o json`, then `byreal-cli polymarket funding status --type deposit -o json`. Report submitted evidence first, then the status readback.

Common failure mode to avoid: calling `funding deposit --amount 10 --execute -o json` in the same turn the user said "deposit 10 USDC", treating the user's original request as the confirmation. The user's first message is intent; the confirmation must come AFTER they see the dry-run ticket. The same rule applies to withdrawals — never `funding withdraw --execute` without a preceding dry-run ticket and an explicit user confirm.

## Error And Readback Rules

- Not found, ambiguous, unavailable, not cancelable, and position/order missing errors stop the write flow. Show candidates or ask for a narrower choice when CLI output provides them.
- `INVALID_PARAMETER`, minimum/maximum/precision failures, and `INSUFFICIENT_BALANCE` are terminal for the current confirmation; report the constraint and wait for a new user choice.
- `PREVIEW_EXPIRED` or missing/expired preview snapshot/token requires a fresh preview/dry-run and confirmation message.
- `PROXY_WALLET_UNAVAILABLE` triggers the automatic proxy deploy flow as a fallback when preflight did not already handle it. `PRIVY_NOT_CONFIGURED`, missing EVM wallet, missing runtime config, or a failed deploy command stops the flow.
- `STATUS_AMBIGUOUS` allows one status readback; if still ambiguous, report ambiguity and do not repeat execution.
- If a CLI command returns a signature, order id, or operation id without an explicit error, treat the action as submitted. Do not retry execution blindly; report submitted evidence plus status/balance/portfolio/funding/account readback, including stale indexing when present.

## Output Rules

- Use narrow-screen stacked output: title, optional caveat, then up to 5 numbered items or a short ticket. Localize visible labels.
- One Event, Market, option, position, or order per item. Put only the item title on the numbered line; put `Price:`, `Volume:`, `Liquidity:`, status, and position/order fields on separate indented lines. Exception: matchup availability and selected market option rows may use one compact `**Option** - $X` line as shown below.
- Use one numbered list per reply. Keep related markets, selected-market options, positions, and orders as separate reply types rather than mixing them in one message.
- Market-candidate items stay market-level only: title, explicit `Status`, `Top option`, `Price`, `Volume`, `Liquidity`, and `Market date` only when the user asks for timing/deadline/settlement.
- No-direct-market replies stay candidate-level only: exact-miss sentence, `Related markets`, related Event/Market titles, optional `Volume:` / `Status:`, then inspection prompt. Prices, options, YES/NO rows, separators, and nested lists belong to the later selected-market reply. If the exact Event was found but its full detail lacks the requested market type, use only `No matching market in event shape`; no related markets or fallback winner rows.
- Read-only candidate replies end with the final prompt from their template. Use inspection wording such as `Tell me which one you want to inspect.` or `Reply with an option number to view details.`
- Convert binary YES into a natural option such as `Mexico wins`. Show NO only when requested or selected by CLI.
- For requested NO, show it as the negated natural proposition, such as `Belgium does not win`, when the CLI returned the direct NO token. Do not display or trade unrelated outcomes as the user's NO.
- External schedule times (when sourced beyond CLI) need verification and `YYYY-MM-DD HH:mm UTC` plus explicit local timezone when shown. `endDate` / `umaResolutionStatus` handling is in Role.
- Keep raw IDs/JSON/internal policy out of normal replies; truncate useful wallet/order/address references.
- Self-check before sending read-only replies: no tables, code fences, slash-compressed fields, pipe-compressed option/metric rows, decorative dividers, raw YES labels, nested candidate outcomes, unrequested NO, schedule inference, start/kickoff/today wording, favorite/probability wording, or trade/funding/proxy prompts unless asked. Preserve Markdown `**` markers from the selected template.
- Limit fill wording: buy limits may fill at the limit price or lower; sell limits at the limit price or higher. Not "below" or "above" the limit price.
- Direction matters when comparing fill price to current market. A BUY filled at a price LOWER than the current ask is better than market; HIGHER is worse. A SELL filled HIGHER than the current bid is better than market; LOWER is worse. Never invert this — do not frame a BUY filled above the current ask (or a SELL filled below the current bid) as "better than market", "favorable fill", or any equivalent positive judgment in any language. If you describe fill quality at all, get the direction right; if uncertain, just report the literal numbers.
- No anticipation, encouragement, or speculative outcome language such as "settles tonight", "looking forward to it", "not your fault", or "you may be mistaken". Hypothetical payouts belong only inside trade-ticket `If <outcome>` lines with neutral phrasing.

Event candidate shape:

```text
Events

1. **World Cup Group A Winner**
   Volume: $182K
   Status: active

2. **NBA Champion**
   Volume: $1.2M
   Status: active

Tell me which event you want to inspect.
```

Market candidate shape:

```text
Markets

1. **World Cup Group A Winner**
   Top option: **Mexico ($0.575)**
   Volume: $663K

2. **World Cup Group A Second Place**
   Top option: **South Korea ($0.315)**
   Volume: $66K

Tell me which market you want to inspect.
```

No direct market shape — use this exact shape. One language per reply (match the user's reply language); translate the headline sentence and the `Related markets` heading. Related items show title and optional Volume only. Do not add `endDate`, match date, kickoff time, settlement window, or any timing line. Do not mix labels from two languages in the same reply.

Canonical English shape (translate prose for non-English replies):

```text
I don't see a direct **Mexico vs. South Africa** market.

Related markets

1. **Mexico vs. Korea Republic**
   Volume: $231K

2. **World Cup Group A Winner**
   Volume: $969K

Tell me which one you want to inspect.
```

No matching market in event shape — use when the Event is selected/found, but current full CLI detail does not return the user's requested spread, handicap, over/under, total, prop, or other specific Market type. Do not list other Markets, related candidates, prices, counts, or alternatives in this reply. Word it as "current visible data does not show/return it", not as a product-wide unsupported claim.

```text
The current visible Polymarket data does not show a **<requested market type>** market for **<event title>**.
```

Invalid for this shape:

```text
The Event only has 3 markets: Netherlands, Draw, Japan.
```

Matchup availability shape:

```text
**Mexico vs. South Africa markets**

1. **Mexico wins** - **$0.685**
2. **Draw** - **$0.205**
3. **South Africa wins** - **$0.105**

Tell me which one you want to inspect.
```

Selected market shape:

```text
**World Cup Group A Winner**

1. **Mexico** - **$0.575**
   Volume: $182K
   Liquidity: $139K

2. **South Korea** - **$0.21**
   Volume: $73K
   Liquidity: $83K

Reply with an option number to view details.
```
