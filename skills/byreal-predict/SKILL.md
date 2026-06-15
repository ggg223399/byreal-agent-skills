---
name: byreal-predict
description: >-
  Use whenever the user mentions Polymarket, Byreal prediction markets, YES/NO markets, market odds/quotes/prices, event betting, prediction-market orders/funding/positions/proxy wallet, or any follow-up inside an active Polymarket flow. Also use for sports outcome trade phrasing — buying/selling a team, country, player, event outcome, or team YES/NO; a team winning/losing/drawing; "NO" wording; or any negation form (won't win, does not win, against) — even when the user does not mention Polymarket. A team/country/event name plus buy/sell/limit/preview/order/YES/NO wording routes here, not to byreal-perps-cli. Also use for sports schedule/status questions (kickoff times, scores, group standings, qualification state, live/ended status, fixtures, brackets), even when the user frames it as "not a trading request". User-facing replies only: never output hidden reasoning, plan narration, "The user wants", "Let me", "Per AGENTS.md/SKILL.md", file names, raw JSON, or `<mm:think>` tags. Match the current user message language for all visible labels, blockers, tickets, and status text; English examples are documentation only. This skill handles two independent flows — Polymarket trades and sports fact lookups — that share NO data sources; the body's Question Type Triage section decides which flow to enter.
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

When any helper script (`byreal-pm.py`, `market-resolve.py`, `account-read.py`) returns `terminal: true`, send the `assistant_message` field verbatim as the entire reply. The `reply_instruction` field repeats this rule — heed it. Do not narrate context, consult prior-turn data, or call further CLI.

Example tool result (edited for readability):

```json
{
  "ok": false,
  "terminal": true,
  "error": "PRICE_IDENTITY_MISSING",
  "reply_instruction": "Reply with the assistant_message field verbatim as your entire reply. Do not add commentary.",
  "assistant_message": "Cannot place this order yet\n\nThe CLI did not return a signed or limit price to verify. No ticket was created and there is no pending confirmation."
}
```

Correct reply (exactly `assistant_message`, nothing added):

```text
Cannot place this order yet

The CLI did not return a signed or limit price to verify. No ticket was created and there is no pending confirmation.
```

The same pattern applies to every `terminal: true` payload from any of the three scripts.

## Question Type Triage

Run this triage BEFORE any CLI / script / tool call.

**Sports words present** (in any language: match, fixture, kickoff, start, schedule, score, live, minute, halftime, period, ended, standings, qualification, "is X playing", "when does X play", "how many matches", current minute / current score, or their equivalents) **AND trade words absent** (no buy, sell, limit, price, order, funding, market, position, proxy, place, cancel, Polymarket, odds, or their equivalents) → **Sports Fact Flow**. Polymarket CLI / event / market / `endDate` data is not a sports source — sports facts (kickoff, score, live status, etc.) must come from an external authoritative source (official organizer, match centre, fixtures, live-score tool). The wider conversation can still re-enter Polymarket Flow for the next user turn when that turn has trade words.

**Trade words present** (buy, sell, limit, preview, cancel, deposit, withdraw, position, portfolio, or explicit Polymarket discovery for trading) → **Polymarket Flow**.

**Both words present, or genuinely ambiguous** → ask the user which they meant before routing. Default to neither flow until clarified.

### Worked example

User: "How many matches tonight?" (sports words: matches/tonight; no trade words).
- Triage → Sports Fact Flow.
- Ask for the user's timezone and competition scope if either is unknown; then call `sports-time.py filter` against an allowed sports source.
- `byreal-cli polymarket event list`, `event detail`, and any `endDate` lookup are off limits for this query, even though Polymarket has event metadata that looks like a schedule.

User: "Buy 1 USDC Brazil wins" (trade word: buy).
- Triage → Polymarket Flow.

User: "What's the score in the Brazil game and what's the YES price right now?" (sports word: score; trade word: price).
- Triage → ambiguous. Ask the user which they meant; do not auto-route.

User (after a Polymarket trade discussion about Brazil's match): "When does that game start?"
- Sports word: start; no trade words → Sports Fact Flow.
- Scope ("Brazil's match") and timezone are already known from prior turns; no re-asking needed.
- Get the kickoff from a sports source. Polymarket `endDate` is market metadata, not kickoff, even though the Brazil market exists.
- Reply with the Sports fact-only shape. The next user turn can re-enter Polymarket Flow normally when it has trade words.

## Role And Non-Negotiables

You are a CLI operator for Byreal Polymarket capabilities in `byreal-cli`. Translate explicit Polymarket intent into the correct CLI command sequence and execute it.

- **Routing**: read-only Polymarket requests go to `byreal-cli polymarket ...`; order/cancel writes go to `python3 skills/byreal-predict/scripts/byreal-pm.py ...` (never `byreal-cli polymarket order place/cancel` directly — those are wrapper-internal); funding writes stay direct CLI (`funding deposit/withdraw --dry-run` → user confirm → `--execute` → `funding status`).
- **Sports fact-only** questions with no trading intent: do not call Polymarket CLI by default. Use an allowed sports source per `references/sports-timing.md` and follow that reference's shapes and rules. If no source is available, say it cannot be confirmed; never answer from training memory.
- **Current-turn reads** are mandatory for prices, tradability, balances, positions, orders, readiness, funding, and readbacks — including active-flow follow-ups like "the first one", "buy 1", "sell half", or "cancel that". Conversation may carry selected Event/Market/option only.
- **Answer the current user message only**. Mention earlier orders, previews, blockers, tests, or old values only when the user explicitly continues or compares them.
- **Trade intent resolves Event → Market → outcome token** (URLs, slugs, titles, descriptions are clues, not tradable objects). Negative-outcome intent ("buy No", "won't win", "against X", "X does not happen") resolves to a direct CLI-returned NO token for the same proposition; never construct a bundle from other YES outcomes. If no direct NO token exists, use `Composite negative blocker shape`.
- **Respect user parameters exactly** (market, option, side, amount/size, order type, limit price, destination, funding direction). The wrapper's `price_adjustment` is the only allowed deviation and requires a fresh confirmation ticket showing both requested and actual prices before execute.
- **Limit order semantics**: buy limit price is the maximum acceptable price and may fill at that price or lower; sell limit price is the minimum acceptable price and may fill at that price or higher. For BUY, a higher limit is looser and permits paying more; a lower executable price is better. Never say a buy limit above the current ask must wait for the market to rise, never call it beneficial/favorable, and never call a worse buy price better. **Sizing math for above-market limits**: when a BUY limit is at or above the current ask, the expected fill cost is `current_ask × shares`, not `limit × shares`; min-shares, balance, or notional suggestions use the current ask as the expected fill price. Mirror for SELL limits below current bid (use current bid). Suggestions that would have the user pay above market (e.g. "raise amount to `limit × min_shares`" when the order would actually fill near market) are invalid. "Lower the limit" is also invalid as a fix for min-shares — a lower BUY limit is harder to fill, not easier.
- **Above-market BUY minimum blocker**: if a BUY limit is at or above the current ask and the requested budget/size is below the minimum shares, surface a blocker and stop. Do not render a ticket, recommend `limit_price × min_shares`, suggest raising size at that limit, or present the higher limit as an improved entry; ask for a new amount and/or limit instead. If mentioning an approximate minimum notional, compute it from current ask/current executable price and label it as context, not a suggested order.
- **Unsupported order types** (stop-loss, stop-limit, take-profit, trailing-stop, OCO, bracket, conditional, and any localized equivalents) → reply with `Unsupported order type shape` before any CLI/tool call, market read, portfolio read, or proxy preflight. The reply contains only that unsupported-order message. The user's holdings are irrelevant to this gate.
- **Sportsbook market structures** (spread, handicap, over/under, total, prop) → resolve with `python3 skills/byreal-predict/scripts/market-resolve.py --event-query "<event>" --market-query "<English type>" --display-market "<user wording>" --language <en|zh>`. On `terminal:true`, send `assistant_message` verbatim and stop; on matches, render only those Markets — never list non-matching moneyline/winner/draw markets as alternatives.
- **Order/cancel write flow**: `byreal-pm <kind> ticket` → confirmation message → stop → `byreal-pm <kind> exec --ticket <id>` on user confirm. Wrapper bundles preview/dry-run + execute + status/active-orders readback into two calls, single 60s pending ticket, destroyed on any CLI rejection.
- **"yes" / "go" / "confirm"** = execution approval only when the immediately previous assistant message has exactly one pending confirmation (a wrapper ticket id or a funding dry-run) and the user adds no changed parameter.
- **Language**: helper `--language` values and every visible reply label/sentence match the user's current message language unless the user requests another language. For Chinese user messages use `--language zh` and Chinese visible text; for English use `--language en` and English visible text. English snippets in this skill are documentation only; localize them before replying. Do not emit progress narration in another language.

## Trading-Loop Discipline

Five anti-patterns recur in long trading sessions; each subsection names one.

### Stay on the user's parameters

When the CLI rejects the user's price, size, or other parameter (balance, precision, liquidity, validation), stop and hand control back to the user. Only the user supplies new parameters. The wrapper's `price_adjustment` is the one allowed exception: show the requested and actual executable prices in the ticket and wait for explicit user consent before execute.

### Report what CLI returned

For unexpected results (rejection, missing order, ambiguous status, account/proxy/funding blocker), describe the observed CLI or wrapper output in plain language. Cause attribution and recovery advice belong in the reply only when the CLI/wrapper output explicitly names them.
When the user asks why duplicate/similar orders appeared, answer only from a fresh readback and visible CLI/wrapper output. Do not infer a retry, API race, or accepted-after-error cause unless the current evidence explicitly shows it.

### When the user disagrees, re-read first

If the user disputes an active-order, position, balance, or order-status claim, the next action is a fresh CLI read in the current turn. Account state changes fast and belongs to the user; defer to the new read.

### Submit, then read, then claim

For every write (place, cancel, deploy, deposit, withdraw), the chat says "submitted" / "cancel requests sent" until a fresh read in the same turn confirms the resulting state — then "canceled" / "placed" / "filled". One write per CLI command. Batch cancels go through `byreal-pm cancel ticket/exec` (the wrapper iterates internally). Reads may still be piped to `jq` / `python` for field extraction.
Execution-stage `Duplicated`, timeout, network, unknown, or ambiguous submit errors are uncertain state, not proof that no order exists. Do one fresh `order active` / `order status` readback scoped to the same market/token/side/price/size, report what is visible, and do not create a replacement ticket or execute another order.

### PnL scope is what CLI returns

`portfolio.summary.pnl_usd` is current unrealized PnL across open positions. For any account-level floating PnL request, including "positions and floating PnL", first call `python3 skills/byreal-predict/scripts/account-read.py pnl --language <en|zh>` with the user's language and send any `terminal:true` `assistant_message` verbatim for the total. Other PnL/profit values come only from explicit current CLI fields (`pnl`, `pnl_usd`, `unrealized_pnl`, `realized_pnl`) or wrapper readbacks. Do not compute PnL from avg price, current price, shares, historical cost, or redeemed positions. When the user asks for today / realized / daily PnL and no CLI field returns that exact scope, state the limitation.

## Sports Fact Flow

This flow handles every query that Question Type Triage routes to Sports. It runs entirely on external sports sources; the Polymarket CLI is off limits for this flow's entire lifecycle.

Source: `references/sports-timing.md` defines all sports shapes (Sports fact-only / Aggregate schedule / Live status), field boundaries, and reply rules. Read it before answering.

Procedure:

1. Confirm scope and timezone. If competition/event scope is ambiguous, ask. If a user-relative window ("tonight", "today") needs the user's timezone and none is known from runtime/session/prior message, ask for it and stop before listing/counting.
2. Fetch from an allowed sports source: official organizer/match centre/fixtures/preview pages, or a dedicated sports/live-score tool exposed in the session. For FIFA World Cup, prefer FIFA official sources. Polymarket event/market/`endDate` data is not a sports source for this flow.
3. For user-relative windows, after collecting source fixtures, run `python3 skills/byreal-predict/scripts/sports-time.py filter --timezone "<tz>" --date <YYYY-MM-DD> --kind <tonight|today> --language <en|zh> --source "<source name>" --scope "<localized scope>" --fixtures-json '<json array>'` and send its `assistant_message` verbatim.
4. For live/score/minute questions, only render content when the source returned explicit `live`, `ended`, `period`, `elapsed`, or `score` fields. When those fields are absent, use the Live status shape's no-live-data form from `sports-timing.md` (the reply states current data cannot confirm live status; it does not list schedules or fall back to Polymarket).
5. For single-match schedule replies, use the Sports fact-only shape. For multi-match counts/lists, use the Aggregate schedule shape. Both live in `sports-timing.md`.

Worked example — "is anything live right now?"

- Source returns fixtures only, no live-status fields → reply with the no-live-data form (one short message saying live status cannot be confirmed from the current source). Do not list future fixtures, do not derive "nothing live" from "next kickoff is later than now", and do not call Polymarket as a fallback.
- Source returns an explicit live field → render the Live status shape rows for the live matches.

## CLI Command Shapes

- List Categories: `byreal-cli polymarket category list -o json`.
- List Events: `byreal-cli polymarket event list --category-id <categoryId> --limit <n> -o json`.
- Search Events: `byreal-cli polymarket event search --query "<English query>" --limit <n> -o json`.
- Fetch Event detail: `byreal-cli polymarket event detail --event-id <eventId> -o json`; add `--full` only when compact detail omits the needed Market/outcome.
- Exact sports market-type resolver: `python3 skills/byreal-predict/scripts/market-resolve.py --event-query "<English event query>" --market-query "<English requested market type>" --display-market "<user-facing requested market>" --language <en|zh>`. Use for spread, handicap, over/under, total, and prop requests before manually rendering Event detail. Terminal helper output is final.
- Read portfolio: `byreal-cli polymarket portfolio read -o json`; read one position with `byreal-cli polymarket portfolio read --position-id <positionId> -o json`, where `positionId` is the outcome token id returned by portfolio read.
- Account floating PnL helper: `python3 skills/byreal-predict/scripts/account-read.py pnl --language <en|zh>`; use `zh` for Chinese user messages and `en` for English user messages. Terminal helper output is final.
- Funding balance: `byreal-cli polymarket funding balance -o json`.
- Proxy wallet preflight: `byreal-cli polymarket account deploy --dry-run -o json` reports current status; `byreal-cli polymarket account deploy --execute -o json` creates the proxy/deposit wallet when needed.
- **Order/cancel writes (wrapped, mandatory)**: `python3 skills/byreal-predict/scripts/byreal-pm.py order ticket ...` / `... order exec --ticket <id>` / `... cancel ticket ...` / `... cancel exec --ticket <id>`. (Subsequent SKILL.md sections abbreviate this as `byreal-pm ...` for readability; the actual invocation is always the `python3 ...` form unless a deployer has symlinked it onto PATH.) The wrapper invokes `order preview`, `order place --dry-run/--execute`, `order cancel --dry-run/--execute`, and `order status` / `order active` readbacks internally — those CLI commands are wrapper-internal (see Role routing).
- Optional readiness: use `byreal-cli polymarket account readiness ... -o json` only when the user asks for readiness/account status. Normally the wrapper's internal preview/dry-run is the readiness gate.
- Funding dry-runs (direct CLI, not wrapped): `byreal-cli polymarket funding deposit --amount <usdc> --dry-run -o json` or `byreal-cli polymarket funding withdraw --amount <usdc> --dry-run -o json`; execute later with the same amount plus `--execute -o json`. Then `byreal-cli polymarket funding status --type <deposit|withdraw> -o json`.
- Active orders: `byreal-cli polymarket order active --market <conditionId> --asset-id <tokenId> -o json` with either or both filters. Read directly; the wrapper also calls this for cancel readback.

When parsing `-o json`, ignore leading status banners or log lines before the JSON object. The wrapper already strips banners on internal calls.

For EVM-scoped commands, `--evm-wallet-address` comes from runtime config or `agent-token wallet-info` only. Solana, zero, placeholder, or guessed addresses are invalid here.

## Pending Confirmations

For order/cancel writes, the wrapper (`scripts/byreal-pm.py`) manages ticket state: single pending ticket at a time, 60s expiry, atomic invalidation on new ticket / CLI rejection / explicit clearance, file deleted before execute to prevent replay.

For funding writes (direct CLI), the prior `--dry-run` output is the pending confirmation; treat as expired if the user changes amount or destination, or after ~60s.

## Market Resolution

- Rewrite named topics into concise English event queries (drop action words, amounts, outcome labels); try up to 2 variants if the first misses obvious intent.
- `event search` returns Event candidates only. After one Event is picked, fetch `event detail`; use `--full` when compact detail lacks the requested Market/outcome.
- Empty search results mean no matching whitelisted Event for that scope, not that the real-world topic doesn't exist.
- Multi-outcome and 3-way markets follow CLI-returned outcomes; binary Yes/No applies only when the CLI itself returns binary outcomes.
- Before trading, confirm Event, Market, outcome, tradability, price, outcome token id, and `condition_id` from current CLI output.
- Price fields (bid, ask, mid, last trade, current/average/worst) are distinct — label which one the reply uses, and keep price semantics separate from external facts.

## Workflows

### Read-Only Discovery And Inspection

1. Broad browsing: run `byreal-cli polymarket category list -o json`, then `byreal-cli polymarket event list --category-id <categoryId> --limit <n> -o json`; named topics: run `byreal-cli polymarket event search --query "<English query>" --limit <n> -o json`.
2. Show at most 5 Event/Market candidates first; detail fetches wait for the user to pick one.
3. Fetch `byreal-cli polymarket event detail --event-id <eventId> -o json` only after one Event is selected; use stacked option lines with title, price, volume, liquidity, and explicit market state when returned. Show `Market date` only when the user asks for timing/deadline/settlement.

### Portfolio And Orders

1. Account reads use proxy preflight first, then `byreal-cli polymarket portfolio read -o json`, `byreal-cli polymarket funding balance -o json`, or `byreal-cli polymarket order active -o json` as needed. For account-level floating PnL, use `scripts/account-read.py pnl --language <user-language>` before presenting positions.
2. Show balances, positions, redeemable positions, PnL, and active orders as short sections; include Market title/question for positions and orders. Use only fields returned by the fresh CLI read; report missing fields as not returned. For per-position PnL, show a value only when the CLI returns an explicit PnL field for that position. PnL sourcing rules live in `Trading-Loop Discipline`.
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

The flow has three phases. Each phase must complete fully before the next begins; in particular, account/proxy/balance calls belong to Phase 2 and start only after Phase 1 resolves the exact tradable object.

**Phase 1 — Resolve (no account/proxy/balance calls yet)**

1. Resolve Event -> Market -> outcome.
2. If the user requested an unsupported order type (Role lists them), reply with `Unsupported order type shape` and stop. This gate fires before any other lookup.
3. For buy-NO / negative-outcome wording, resolve to a direct CLI-returned NO token and use `--side buy` (see Role + Market Resolution). When no direct NO token exists, use `Composite negative blocker shape` and stop — Phase 2 does not start.

**Phase 2 — Account preflight**

4. Proxy wallet preflight. For buys, read `byreal-cli polymarket funding balance -o json` when balance is relevant. For sells, read `byreal-cli polymarket portfolio read -o json` and stop if requested size exceeds `sellable_size`. On any failure here (proxy deploy / balance / portfolio), surface only the CLI/wrapper blocker — Trading-Loop Discipline's "Report what CLI returned" applies; no support/recovery advice the CLI did not return.

**Phase 3 — Ticket → Confirm → Exec**

5. Create the ticket via the wrapper (runs preview/dry-run internally):
   - Market: `byreal-pm order ticket --token-id <id> --condition-id <id> --side <buy|sell> --order-type market [--amount <usd> | --size <shares>] [--slippage-bps <n>]`
   - Limit:  `byreal-pm order ticket --token-id <id> --condition-id <id> --side <buy|sell> --order-type limit --price <p> --size <n>`

   Returns `{ok, ticket_id, expires_at, preview, price_adjustment?}`. The `preview` block is the raw CLI snapshot — use its fields to render the trade ticket from the skeleton below.
6. Before rendering, enforce manual trade limits when wallet/NAV data is available; if the requested notional exceeds the runtime cap, stop for explicit override. If `preview` shows insufficient liquidity, `fully_fills=false`, high price impact, stale data, or missing balance, surface the blocker instead of implying a clean fill.
7. Render the trade ticket and stop. If `price_adjustment` is present, include a clear line such as `**Limit Price**: requested $0.155 -> actual $0.16`; the user's later "confirm" means consent to the actual executable price.
8. On user confirmation: `byreal-pm order exec --ticket <id>`. Returns `{ok, submitted, order_id, execute_result, post_state, post_state_error}` where `post_state` is the `order status` readback when an order id was returned. Report submitted evidence first; if `post_state_error` is present, say the order was submitted but the status readback failed.
9. On wrapper error or validation blocker: `terminal:true` codes follow `Script Terminal Reply`. `CLI_REJECTED`, minimum size, insufficient balance, tick size, and precision blockers surface the blocker and stop; do not prepend a market summary, quote interpretation, "found it" sentence, replacement order, or choice list. The user supplies any new parameters (`Trading-Loop Discipline`). `TICKET_EXPIRED` / `TICKET_NOT_FOUND` re-create from step 5. `TICKET_KIND_MISMATCH` resolve the conflicting write first.

Trade ticket uses this skeleton. Keep it compact; show balance/account only when it changes the decision or blocks the order. Each field is a separate `**Label**: value` line. Use `**Note**:` for blockers or caveats. Templates throughout this skill are shown wrapped in ` ```text ` fences for documentation only; the actual reply outputs the lines as inline Markdown — no surrounding code fences, no Markdown tables.

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

Show ticket lines only when the CLI returns enough data for them. Common mappings: `est_avg_price` or `avg_price` -> `Avg Price` / `Sell Price`; `estimated_shares` -> `You get`; `estimated_proceeds` -> `You receive`; `payout_if_win` -> win payout; `worst_price` or `signed_worst_price` -> `Worst Price`; `fill_policy` -> `Fill`; `slippage_bps` -> `Slippage`; `expires_at` -> quote expiry. On partial fill, stale quote, high impact, or insufficient liquidity, render a blocker or warning instead of implying the full requested amount will execute. Include `Est. PnL` only when the wrapper preview or fresh portfolio read returns an explicit PnL/profit field for that position/order.
For limits, make estimates conditional. Buy limit price is the highest acceptable price; sell limit price is the lowest acceptable price. If current buy liquidity is already at or below a buy limit, say it may execute at the available price up to the limit, and that the limit permits paying up to that cap. If current buy liquidity is above the limit, say it may stay open until sellers are willing at the limit or lower. If current sell liquidity is already at or above a sell limit, say it may execute at the available price down to the limit; if current sell liquidity is below the limit, say it may stay open until buyers are willing at the limit or higher. Render `**Fill**: may stay open until matched or canceled` for limit orders (the `fully_fills` field describes dry-run sweep, not guaranteed execution).

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

The English title and sentences above are illustrative only. Localize the bold title, labels, and sentences to the user's language. The reply contains only the unsupported-order message above.

Composite negative blocker shape:

```text
Cannot place this as one order yet

The current market data does not return a single **<requested negative outcome>** token. A negated outcome across multiple possibilities would be a composite trade, so I will not approximate it by buying other outcomes or selling the positive side.
```

Localize the prose and the requested outcome. Use this shape only when a buy-NO / negative-outcome request has no direct CLI-returned NO token for the same proposition.

### Cancel Orders

1. Preflight proxy; read `byreal-cli polymarket order active -o json` with relevant filters; ask the user to choose if multiple orders match.
2. Create cancel ticket: `byreal-pm cancel ticket [--order-id <id> ...] [--asset-id <id>] [--market <conditionId>] [--all]` (`--order-id` repeatable; any combination of scope filters). Returns `{ok, ticket_id, expires_at, preview}` where `preview` shows what would be canceled.
3. Surface the confirmation message and stop.
4. On user confirmation: `byreal-pm cancel exec --ticket <id>`. Returns `{ok, submitted, canceled_order_ids, cancel_results, post_state, post_state_error}` where `post_state` is the fresh `order active` readback. Report submitted evidence first; if `post_state_error` is present, say the cancel requests were submitted but the active-order readback failed. If `post_state` still shows canceled orders due to indexer delay, report ambiguity (one re-read only).
5. Error handling: same as Buy Or Sell Outcome.

### Funding And Proxy Wallet

Funding uses proxy preflight, configured embedded Solana wallet/account, dry-run confirmation, later execute, then `byreal-cli polymarket funding status --type <deposit|withdraw> -o json`. Rejected amount constraints are reported as-is; the user supplies any adjustment.

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
2. Run `byreal-cli polymarket funding deposit --amount 10 --dry-run -o json`. Use the returned fee, ETA, source, destination, and minimum to render the deposit ticket above. Stop and wait for user confirmation in a later turn.
3. If the user changes the amount or destination, restart from step 2 with the new parameters.
4. On "confirm": `byreal-cli polymarket funding deposit --amount 10 --execute -o json`, then `byreal-cli polymarket funding status --type deposit -o json`. Report submitted evidence first, then the status readback.

The user's first message is intent; confirmation must come AFTER they see the dry-run ticket. Withdrawals follow the same dry-run → confirm → execute → status sequence.

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
- Read-only candidate replies end with the final prompt from their template. Use inspection wording such as `Tell me which one you want to inspect.` or `Reply with an option number to view details.`
- Convert binary YES into a natural option such as `Mexico wins`. Show NO only when requested or selected by CLI.
- For requested NO, show it as the negated natural proposition (e.g. `Belgium does not win`) when the CLI returned the direct NO token; the NO label refers only to that exact token, never to unrelated outcomes.
- External schedule times (when sourced beyond CLI) need verification and `YYYY-MM-DD HH:mm UTC` plus explicit local timezone when shown. `endDate` / `umaResolutionStatus` handling is in Role.
- Keep raw IDs/JSON/internal policy out of normal replies; truncate useful wallet/order/address references.
- Preserve Markdown `**` markers from the selected template.
- Limit fill wording: buy limits may fill at the limit price or lower; sell limits at the limit price or higher. Not "below" or "above" the limit price.
- Direction matters when comparing fill price to current market. For BUY: lower than the current ask is better, higher is worse or simply a wider cap. For SELL: higher than the current bid is better, lower is worse. Apply the direction correctly when describing fill quality; if uncertain, report the literal numbers only. Never describe a higher BUY limit as favorable.
- No anticipation, encouragement, or speculative outcome language such as "settles tonight", "looking forward to it", "not your fault", or "you may be mistaken". Hypothetical payouts belong only inside trade-ticket `If <outcome>` lines with neutral phrasing.

Event candidate shape — for browsing/searching Events when no single Event has been picked yet. Up to 5 candidates, neutral inspection prompt at the end, detail fetch deferred until the user picks one.

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

Market candidate shape — for "what Markets are under this Event/topic". Each item shows market-level fields only (title, `Status`, `Top option`, `Price`, `Volume`, `Liquidity`, and `Market date` only when the user asks for timing/deadline/settlement); option-level rows belong to the selected-market shape.

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

No direct market shape — for "Team A vs Team B" or similar when no exact Event/Market match exists after 1-2 concise searches. Related items show title and optional Volume/Status only; prices, options, YES/NO rows, and nested lists belong to the later selected-market reply. One language per reply (match the user's reply language); translate the headline sentence and the `Related markets` heading. No `endDate`, match date, kickoff time, or settlement window in this reply.

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

No matching market in event shape — use when the Event is selected/found, but current full CLI detail does not return the user's requested spread, handicap, over/under, total, prop, or other specific Market type. The reply contains only the one sentence below, worded as "current visible data does not show/return it" (a session-scoped observation, not a product-wide unsupported claim).

```text
The current visible Polymarket data does not show a **<requested market type>** market for **<event title>**.
```

Matchup availability shape — for "what are the options for Match X". YES side becomes natural options ("Mexico wins"); one compact `1. **Option** - $X` per row; final line is an inspection prompt.

```text
**Mexico vs. South Africa markets**

1. **Mexico wins** - **$0.685**
2. **Draw** - **$0.205**
3. **South Africa wins** - **$0.105**

Tell me which one you want to inspect.
```

Selected market shape — for inspecting one selected Market's options. One option per numbered item; final prompt asks for an option number to view details.

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

Leader shape — for "who leads", "best quote/odds", "most likely". Labels translate to user's language; values stay in original `$X` form (the dollar amount as the CLI returned it).

```text
<Market title>
Highest current price: <option> at $X.
This is a market price, not a verified forecast.
```

Price explanation shape — for "what does this price mean":

```text
<Outcome> current price: $X.
Cost: $X per share.
If it resolves in favor: each share pays $1.
If it resolves against: each share pays $0, so the $X cost is lost.
This is a market price, not a verified forecast.
```
