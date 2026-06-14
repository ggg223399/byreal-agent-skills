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

Use this compact shape after source verification.

**Shape identity = line order + content type, NOT the literal English labels below.** The shape has 6 lines: bold match title, kickoff in UTC, the user's local time, competition, venue, source.

**Localization rule (mandatory):** Labels MUST match the user's reply language. If the user writes in a non-English language, output every label in that language — do not output the English labels below as-is. Labels are translated words, not icons. Date format stays `YYYY-MM-DD HH:mm` plus the explicit timezone; team names, venue names, and source names stay in their original/canonical form unless a widely-used localized form exists.

**`Your time` vs `Event local time`:** "Your time" is the **user's** timezone when known (from session settings, prior conversation, or explicitly stated). It is NOT the venue's local time. A Dallas kickoff at 20:00 UTC-5 is `Your time` only for a user in UTC-5; for a Beijing user, `Your time` is 04:00 UTC+8 the next day. If the venue's local time is asked for separately, use a distinct label such as `Event local time` (localized) on a separate line; otherwise do not output it.

Reply with the shape only. The only Markdown allowed is the bold match title. Do not add intro/outro, emoji, icon labels, bullets, countdowns, relative dates, rankings, team records, historical head-to-head facts, or analysis.

Canonical English shape (translate labels for non-English replies):

```text
**<Team A> vs <Team B>**

Kickoff: <YYYY-MM-DD HH:mm UTC>
Your time: <YYYY-MM-DD HH:mm UTC+offset>
Competition: <competition and group/round when returned>
Venue: <venue when returned>
Source: <source name>
```

Do not add other timezone conversions, relative labels, emoji, tables, bullets, countdowns, or live/started/ended claims unless the source explicitly returned live status.

## Generated Schedule References

Static schedule data becomes stale quickly. Use a generated schedule reference only when it includes:

- `Generated at`
- `Source`
- `Stale after`
- Absolute UTC time
- Local timezone only when explicitly available

If the generated reference is stale, do not use it for match timing.

## Worked Example

User: When does Netherlands vs Japan kick off?

Correct flow:

1. Treat as a sports-schedule question that requires source verification. The "this is a factual question, not a trading request" framing does not waive verification — this reference applies.
2. Look for an allowed schedule source: official FIFA match centre/fixtures/preview pages, a generated schedule reference with the fields listed above, or a CLI/source that returns explicit kickoff time.
3. If a source has the match: reply using `Sports fact-only shape`. Do not add a countdown, table, emoji, or live/started claim unless the source explicitly returns live status.
4. If no source is available in this session: reply that the kickoff time cannot be confirmed from current data. Do not guess.

Common failure mode to avoid: answering "World Cup Group C, June 25, time TBD" from training memory. Training memory is not a current source for schedules — groups, dates, and times shift, and getting them wrong here is harder to catch than getting a price wrong. Even when the question feels purely factual, the source step is still required.
