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
- Fixture lists and live-status questions are different reads. Use official fixture/match-centre sources for schedules; use an official match centre or a dedicated live-score source that returns explicit status fields for "live", "in progress", "current score", or "minute" questions. A preview article or fixture list without status fields is not enough to say no match is live.
- Sports fact-only replies are compact text: no Markdown tables, pipe characters (`|`), emoji, bullets, decorative lines, countdowns, extra timezone tables, or `today` / `tonight` / `tomorrow` labels. Use absolute dates, UTC, and the user's local timezone when known.
- Multi-match/count replies may use one numbered list. Keep one source line at the end unless items came from different sources.
- Resolve user-relative windows before filtering. "Tonight" means the user's local evening/night window, defaulting to 18:00 through 06:00 the next local day when the user did not specify a different range. "Today" means the user's local calendar day. If the user's timezone is not known from runtime/session/prior message, ask the user for their timezone first and stop; do not filter, count, list, or answer from UTC as a fallback.
- Relative-window filtering order is mandatory: define the user's local window, convert that window to UTC for source lookup, parse each candidate kickoff with its timezone, convert each kickoff back to the user's timezone, then filter/count/list by the converted local kickoff. Do not filter by the source's UTC calendar date before conversion.
- For user-relative windows, run `python3 skills/byreal-predict/scripts/sports-time.py filter --timezone "<timezone>" --date <YYYY-MM-DD> --kind <tonight|today> --language <en|zh> --source "<source name>" --scope "<localized scope>" --fixtures-json '<json array>'` after collecting source fixtures. Send the helper's `assistant_message` verbatim as the entire reply. Do not manually recalculate, rename fields, mention outside-window fixtures, or add commentary.
- Never label a UTC time as `Your time` unless the user's timezone is explicitly UTC+0. If the user's timezone is unknown, omit `Your time` instead of copying the UTC line.
- `Kickoff` always means the absolute UTC kickoff in these shapes. The local conversion belongs only on `Your time`. If a source returns only local time, convert it to UTC before writing `Kickoff`; if the source timezone is ambiguous, use another source or say the time cannot be confirmed.
- Do not infer live/started/ended state from kickoff time or the current clock. Say only the scheduled kickoff time unless an explicit sports status source returns `live`, `ended`, `period`, `elapsed`, or `score`.
- For "is anything live now?" first check a source that can return live status across the relevant competition/day. Do not answer "no live matches" after only checking future scheduled fixtures or the next kickoff time. Include any explicitly live match returned by the source even when its kickoff falls outside a prior "tonight" fixture window.
- If no explicit sports live-status fields are available, say the current available data cannot confirm the real-world match status.
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

## Aggregate schedule shape

Use this for "how many games tonight/today", fixture lists, or multi-match schedule questions after source verification.

```text
**<Competition or scope>**
Window: <YYYY-MM-DD HH:mm> to <YYYY-MM-DD HH:mm UTC+offset>
Matches: <count>

1. **<Team A> vs <Team B>**
Kickoff: <YYYY-MM-DD HH:mm UTC>
Your time: <YYYY-MM-DD HH:mm UTC+offset>

2. **<Team C> vs <Team D>**
Kickoff: <YYYY-MM-DD HH:mm UTC>
Your time: <YYYY-MM-DD HH:mm UTC+offset>

Source: <source name>
```

If the timezone is unknown, ask for the user's timezone and stop before using "tonight" or any other user-relative window. If the user asked for a UTC day/window, replace `Window` with that UTC window and omit `Your time`.

Reply with the shape only. Do not append outside-window fixtures, "other matches", commentary, or relative labels after the source line.

Worked conversion example: for a UTC+8 user asking on 2026-06-15, "tonight" is 2026-06-15 18:00 to 2026-06-16 06:00 UTC+8, which is 2026-06-15 10:00 to 2026-06-15 22:00 UTC. A fixture at 2026-06-15 17:00 UTC converts to 2026-06-16 01:00 UTC+8 and is inside the user's tonight window.

## Live status shape

Use this for "is anything live now", score, minute, started, or ended questions.

When explicit live fields exist:

```text
**Matches in progress**
Checked: <YYYY-MM-DD HH:mm UTC>

1. **<Team A> vs <Team B>**
Status: <live/halftime/ended/etc. from source>
Score: <score when returned>
Minute: <minute/period when returned>

Source: <source name>
```

When no explicit live fields are available:

```text
I cannot confirm live matches from the current data.

The source returned fixtures only, not live status, score, or minute fields.
```

Do not use kickoff time plus wall-clock time to fill `Status`, `Score`, or `Minute`.

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

## Worked Example 2: live minute / score

User: How many minutes into the match are we? / What's the current score?

Correct flow:

1. Check whether an allowed source has returned explicit live-status fields (`live`, `ended`, `period`, `elapsed`, `score`). The default Polymarket CLI does not return these.
2. If a source has live fields: reply with what those fields say, in a compact label-value structure consistent with the Sports fact-only shape.
3. If no live source is available in this session: reply that the current Polymarket data cannot confirm the live minute or score. Do not estimate from kickoff time minus the current wall clock. Do not invent a score.

Common failure modes to avoid:

- Answering "30th minute, 0-0" by subtracting kickoff time from the current clock. Matches get delayed, suspended, paused, or rescheduled; elapsed wall-clock time is not the same as match minute.
- Saying "the match should be live now" or "should be in the second half" — those are inferences from the schedule plus current time, not facts from a live source.
- Inventing a 0-0 default when no score field exists. No data is not the same as 0-0.
- Saying "the next fixture starts at 17:00 UTC, so nothing is live now" after checking only future fixtures. That misses matches already in progress and is still schedule inference.
- Writing `Your time: 2026-06-15 17:00 UTC` when the kickoff line is also `2026-06-15 17:00 UTC`. That is UTC repeated, not a user-local conversion, unless the user is explicitly in UTC+0.
