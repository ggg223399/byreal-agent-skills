# Sports Timing Reference

Use this reference for any sports timing/status question — kickoff time, score, group standing, qualification state, live/ended status, settlement — regardless of whether the question references a Polymarket market. Reclassifying a request as "just a factual question, not trading" does not exempt it from these rules. If this reference is loaded, it applies.

## Field Boundaries

- `endDate` / `end_date`: Polymarket/Gamma market metadata. It is not proof of kickoff, final whistle, live state, market close, or settlement completion.
- `umaResolutionStatus`: UMA settlement workflow only. `proposed` means a resolution proposal is pending; `resolved` means the market resolved. It is not a live-score or match-status field.
- `closed`, `active`, `acceptingOrders`, `enableOrderBook`: market tradability fields. They say whether the market can be traded, not whether the real-world match is live or ended.
- `live`, `ended`, `period`, `elapsed`, `score`: sports live-status fields. Use these only when explicitly returned by an allowed source such as `scripts/polymarket-sports.py`; do not confuse them with Gamma market metadata.

## Reply Rules

- Match timing in price/market-availability replies appears only when the user asks for it.
- For sports fact-only schedule/status questions, use an allowed current source: `scripts/polymarket-sports.py`, official organizer pages, official match centres, official fixture/preview pages, and dedicated sports/live-score tools exposed in the session. For Polymarket Sports-covered leagues such as World Cup (`fwc`) and MLB (`mlb`), use `scripts/polymarket-sports.py` first for live/status/score/minute.
- Fixture lists and live-status questions are different reads. Use official fixture/match-centre sources for schedules; use a source that returns explicit status fields (`live`, `ended`, `period`, `elapsed`, `score`) for live/in-progress/score/minute questions. A preview article or fixture list without status fields is insufficient to conclude no match is live.
- Do not use web search for covered-league live/status/score/minute while `scripts/polymarket-sports.py` is available. If that helper fails, say the live-status source cannot confirm the answer.
- Sports fact-only replies use compact text with absolute dates (`YYYY-MM-DD HH:mm UTC`) and the user's local timezone when known. (Shape sections below enforce the stacked structure.)
- Multi-match/count replies use one numbered list. One source line at the end unless items came from different sources.
- Resolve user-relative windows before filtering. "Tonight" means the user's local evening/night window, defaulting to 18:00 through 06:00 the next local day when the user did not specify a different range. "Today" means the user's local calendar day. If the user's timezone is not known from runtime/session/prior message, ask for it first and stop before filtering, counting, listing, or answering.
- Relative-window filtering order is mandatory: define the user's local window, convert that window to UTC for source lookup, parse each candidate kickoff with its timezone, convert each kickoff back to the user's timezone, then filter/count/list by the converted local kickoff (never by the source's UTC calendar date before conversion).
- For user-relative windows, run `python3 skills/byreal-predict/scripts/sports-time.py filter --timezone "<timezone>" --date <YYYY-MM-DD> --kind <tonight|today> --language <en|zh> --source "<source name>" --scope "<localized scope>" --fixtures-json '<json array>'` after collecting source fixtures. Send the helper's `assistant_message` verbatim as the entire reply.
- Label `Your time` only when the user's timezone is known and non-UTC+0. When the timezone is unknown, omit the `Your time` line (copying the UTC value is invalid).
- `Kickoff` always means the absolute UTC kickoff in these shapes; the local conversion belongs only on `Your time`. If a source returns only local time, convert it to UTC before writing `Kickoff`; if the source timezone is ambiguous, use another source or say the time cannot be confirmed.
- Scheduled kickoff time is always safe to report. Live/started/ended state, score, and minute require explicit source fields (`live`, `ended`, `period`, `elapsed`, `score`).
- For "is anything live now?", check a source that returns live status across the relevant competition/day first; conclude there are no live matches only when that source confirms it. Include explicitly live matches the source returns even when their kickoff falls outside a prior "tonight" window.
- If no explicit sports live-status fields are available, say the current data cannot confirm the real-world match status.
- Market tradability questions are answered from tradability fields, readiness, preview, dry-run, or order-book signals — not from match timing.
- When the user asks when a market ends or settles and the only available field is `endDate` / `end_date`, label it `Market date` only — this is metadata, not a timing/state claim.

## Sports fact-only shape

Use this compact shape after source verification.

**Shape identity = line order + content type.** Labels below are illustrative; localize them to the user's language. The shape has 6 lines: bold match title, kickoff in UTC, the user's local time, competition, venue, source.

**Localization rule (mandatory):** Labels MUST match the user's reply language. For non-English replies, translate every label. Labels are translated words, not icons. Date format stays `YYYY-MM-DD HH:mm` plus the explicit timezone; team names, venue names, and source names stay in their original/canonical form unless a widely-used localized form exists.

**`Your time` vs `Event local time`:** "Your time" is the **user's** timezone when known (from session settings, prior conversation, or explicitly stated). It is the user's timezone, not the venue's. A Dallas kickoff at 20:00 UTC-5 is `Your time` only for a user in UTC-5; for a Beijing user, `Your time` is 04:00 UTC+8 the next day. When the venue's local time is asked for separately, use a distinct label such as `Event local time` (localized) on a separate line; otherwise it stays out of the reply.

Reply with the shape only. The only Markdown allowed is the bold match title. The reply contains no intro/outro, emoji, icon labels, bullets, countdowns, relative dates, rankings, team records, historical head-to-head facts, or analysis.

Canonical English shape (translate labels for non-English replies):

```text
**<Team A> vs <Team B>**

Kickoff: <YYYY-MM-DD HH:mm UTC>
Your time: <YYYY-MM-DD HH:mm UTC+offset>
Competition: <competition and group/round when returned>
Venue: <venue when returned>
Source: <source name>
```

The reply uses only the 6 lines above — no additional timezone conversions, relative labels, emoji, tables, bullets, countdowns, or live/started/ended claims (unless the source explicitly returned live status, in which case use `Live status shape` instead).

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

Reply with the shape only; it ends at the source line. Outside-window fixtures, "other matches", commentary, and relative labels stay out.

Worked conversion example: for a UTC+8 user asking on 2026-06-15, "tonight" is 2026-06-15 18:00 to 2026-06-16 06:00 UTC+8, which is 2026-06-15 10:00 to 2026-06-15 22:00 UTC. A fixture at 2026-06-15 17:00 UTC converts to 2026-06-16 01:00 UTC+8 and is inside the user's tonight window.

## Live status shape

Use this for "is anything live now", score, minute, started, or ended questions.

When explicit live fields exist, or when `scripts/polymarket-sports.py live/status` returns `terminal:true`, use the helper's `assistant_message` verbatim.

General shape when manually rendering explicit live fields:

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

`Status`, `Score`, and `Minute` come only from explicit source fields.

## Generated Schedule References

Static schedule data becomes stale quickly. Use a generated schedule reference only when it includes:

- `Generated at`
- `Source`
- `Stale after`
- Absolute UTC time
- Local timezone only when explicitly available

Use the generated reference for match timing only while it is within its `Stale after` window.

## Worked Example

User: When does Netherlands vs Japan kick off?

Correct flow:

1. Treat as a sports-schedule question that requires source verification. The "this is a factual question, not a trading request" framing does not waive verification — this reference applies.
2. Look for an allowed schedule source: official FIFA match centre/fixtures/preview pages, a generated schedule reference with the fields listed above, or a CLI/source that returns explicit kickoff time.
3. If a source has the match: reply using `Sports fact-only shape` (countdowns/tables/emoji/live-status claims appear only when the source explicitly returns live status).
4. If no source is available in this session: reply that the kickoff time cannot be confirmed from current data.

Common failure mode to avoid: answering "World Cup Group C, June 25, time TBD" from training memory. Training memory is not a current source for schedules — groups, dates, and times shift, and getting them wrong here is harder to catch than getting a price wrong. Even when the question feels purely factual, the source step is still required.

## Worked Example 2: live minute / score

User: How many minutes into the match are we? / What's the current score?

Correct flow:

1. For covered leagues, call `scripts/polymarket-sports.py live --league <slug>` or `scripts/polymarket-sports.py status --league <slug> --query "<match/team>"` before any web search. Use `fwc` for World Cup and `mlb` for MLB.
2. Check whether an allowed source has returned explicit live-status fields (`live`, `ended`, `period`, `elapsed`, `score`). The default Polymarket CLI does not return these.
3. If a source has live fields: reply with what those fields say, in a compact label-value structure consistent with the Sports fact-only shape.
4. If no live source is available in this session: reply that the current data cannot confirm the live minute or score.

Common failure modes to avoid:

- Answering "30th minute, 0-0" by subtracting kickoff time from the current clock. Matches get delayed, suspended, paused, or rescheduled; elapsed wall-clock time is not the same as match minute.
- Saying "the next fixture starts at 17:00 UTC, so nothing is live now" after checking only future fixtures. That misses matches already in progress and is still schedule inference — live status needs a live-fields source.
- Writing `Your time: 2026-06-15 17:00 UTC` when the kickoff line is also `2026-06-15 17:00 UTC`. That is UTC repeated, not a user-local conversion (omit `Your time` when the user's timezone is unknown or UTC+0).
