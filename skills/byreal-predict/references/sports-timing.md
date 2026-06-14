# Sports Timing Reference

Use this reference for sports markets when the user asks whether a match starts, is live, has ended, or is settling.

## Field Boundaries

- `endDate` / `end_date`: Polymarket/Gamma market metadata. It is not proof of kickoff, final whistle, live state, market close, or settlement completion.
- `umaResolutionStatus`: UMA settlement workflow only. `proposed` means a resolution proposal is pending; `resolved` means the market resolved. It is not a live-score or match-status field.
- `closed`, `active`, `acceptingOrders`, `enableOrderBook`: market tradability fields. They say whether the market can be traded, not whether the real-world match is live or ended.
- `live`, `ended`, `period`, `elapsed`, `score`: sports live-status fields. Use these only when explicitly returned by an allowed source.

## Reply Rules

- Price and market-availability replies do not include match timing unless the user asks for timing.
- If no explicit sports live-status fields are available, say the Polymarket data cannot confirm the real-world match status.
- If the user asks whether a market can be traded, answer from tradability fields, readiness, preview, dry-run, or order-book signals, not from match timing.
- If the user asks when a market ends or settles and the only available field is `endDate` / `end_date`, label it `Market date`, not kickoff, end time, settlement time, today, tonight, tomorrow, pre-match, or in-play.

## Generated Schedule References

Static schedule data becomes stale quickly. Use a generated schedule reference only when it includes:

- `Generated at`
- `Source`
- `Stale after`
- Absolute UTC time
- Local timezone only when explicitly available

If the generated reference is stale, do not use it for match timing.
