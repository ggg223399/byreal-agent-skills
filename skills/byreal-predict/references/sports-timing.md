# Sports Timing Reference

Use this reference for any sports timing/status question — kickoff time, score, group standing, qualification state, live/ended status, settlement — regardless of whether the question references a Polymarket market. Reclassifying a request as "just a factual question, not trading" does not exempt it from these rules. If this reference is loaded, it applies.

## Field Boundaries

- `endDate` / `end_date`: Polymarket/Gamma market metadata. It is not proof of kickoff, final whistle, live state, market close, or settlement completion.
- `umaResolutionStatus`: UMA settlement workflow only. `proposed` means a resolution proposal is pending; `resolved` means the market resolved. It is not a live-score or match-status field.
- `closed`, `active`, `acceptingOrders`, `enableOrderBook`: market tradability fields. They say whether the market can be traded, not whether the real-world match is live or ended.
- `live`, `ended`, `period`, `elapsed`, `score`: sports live-status fields. Use these only when explicitly returned by an allowed source.

## Reply Rules

- Price and market-availability replies do not include match timing unless the user asks for timing.
- For sports fact-only schedule/status questions, actively use an allowed current source when available. Allowed sources include official organizer pages, official match centres, official fixture/preview pages, and dedicated sports/live-score tools exposed in the session. For FIFA World Cup questions, prefer FIFA official sources.
- Sports fact-only replies are compact text: no Markdown tables, pipe characters (`|`), emoji, bullets, decorative lines, countdowns, extra timezone tables, or `today` / `tonight` / `tomorrow` labels. Use absolute dates, UTC, and the user's local timezone when known.
- Do not infer live/started/ended state from kickoff time or the current clock. Say only the scheduled kickoff time unless an explicit sports status source returns `live`, `ended`, `period`, `elapsed`, or `score`.
- If no explicit sports live-status fields are available, say the Polymarket data cannot confirm the real-world match status.
- If the user asks whether a market can be traded, answer from tradability fields, readiness, preview, dry-run, or order-book signals, not from match timing.
- If the user asks when a market ends or settles and the only available field is `endDate` / `end_date`, label it `Market date`, not kickoff, end time, settlement time, today, tonight, tomorrow, pre-match, or in-play.

## Sports fact-only shape

Use this exact compact shape after source verification:

```text
**<Team A> vs <Team B>**

Kickoff: <YYYY-MM-DD HH:mm UTC>
Local time: <YYYY-MM-DD HH:mm UTC+offset or timezone name>
Competition: <competition and group/round when returned>
Venue: <venue when returned>
Source: <source name>
```

If the user asks in another language, localize the labels, but keep the same line-by-line shape. Do not add other timezone conversions, relative labels, emoji, tables, bullets, countdowns, or live/started/ended claims unless the source explicitly returned live status.

## Generated Schedule References

Static schedule data becomes stale quickly. Use a generated schedule reference only when it includes:

- `Generated at`
- `Source`
- `Stale after`
- Absolute UTC time
- Local timezone only when explicitly available

If the generated reference is stale, do not use it for match timing.

## Worked Example

User: 荷兰 vs 日本什么时候开打？

Correct flow:

1. Treat as a sports-schedule question that requires source verification. The "this is a factual question, not a trading request" framing does not waive verification — this reference applies.
2. Look for an allowed schedule source: official FIFA match centre/fixtures/preview pages, a generated schedule reference with the fields listed above, or a CLI/source that returns explicit kickoff time.
3. If a source has the match: reply using `Sports fact-only shape`. Do not add a countdown, table, emoji, or live/started claim unless the source explicitly returns live status.
4. If no source is available in this session: reply that the kickoff time cannot be confirmed from current data. Do not guess.

Common failure mode to avoid: answering "World Cup Group C, June 25, time TBD" from training memory. Training memory is not a current source for schedules — groups, dates, and times shift, and getting them wrong here is harder to catch than getting a price wrong. Even when the question feels purely factual, the source step is still required.
