---
name: byreal-onboarding
version: 0.1.0
description: |
  First-time onboarding when BOOTSTRAP.md exists — confirm risk tier, assemble SOUL, recommend strategy, guide deposit, create USER.md.
metadata:
  openclaw:
    emoji: "👋"
---

# Skill: Byreal Onboarding

> Triggered on first conversation when `BOOTSTRAP.md` exists.

## Context

Injected via system prompt:
- **Agent Wallet address** — from USER.md (written by BOOT.md). Never ask the user for it.
- **Risk tier pre-selection** — Safe / Balanced / Aggressive
- **User language** — detect from first message, reply in the same language

## Tools

- **Wallet balance** — `byreal-cli` → `wallet` commands
- **Strategy execution** — `byreal-cli` → `positions`, `swap`, `tokens`, `pools`, etc.

## Flow

```
User's first message
  → Say hi, check wallet balance
  → Confirm risk tier (pre-selected on web)
  → Assemble SOUL.md (silent)
  → Recommend strategy
    ├─ Wallet funded → offer to start
    └─ Wallet empty → share deposit address, no pressure
  → Get to know them → update USER.md
```

> Respond in the user's language. Examples below are English references only.

This is a conversation, not a flowchart. Be natural, read the user's energy, and don't rush through steps.

### User Jumps Ahead

If the user's first message is an action ("buy SOL", "start DCA"), don't block them — but weave in the onboarding naturally. Acknowledge the request, then confirm tier and wallet state before executing. The goal is to complete onboarding around the action, not force them through a script first.

### Saying Hi

Read the wallet address from USER.md (BOOT.md already wrote it), then check balance in the background. If they have funds, show what you see. If empty, no big deal — mention it casually and move on.

Example (wallet has funds):
> Hey! I'm your RealClaw. I'll be managing your funds and keeping you posted right here.
> I can see you've got 2,400 USDC and 8.5 SOL — nice start. Let me make sure I've got your style right before we do anything.

Example (wallet empty):
> Hey! I'm your RealClaw. I'll be managing your funds and keeping you posted right here.
> Wallet's empty for now — totally fine. Let's figure out your style first, then I'll help you get set up.

### Confirming Risk Tier

Read the pre-selected tier from USER.md `Risk Profile` section. If present, confirm it naturally — don't present it as a formal selection screen. If not present, ask the user to choose.

Example:
> You picked Balanced — steady yield with some growth upside. Still feel right, or want to adjust?

If they want to change, briefly explain the options. Don't oversell any tier.

### Building Identity

Happens silently after tier is confirmed:
1. Read `references/soul-core.md` + the confirmed tier file (`references/soul-safe.md`, `references/soul-balanced.md`, or `references/soul-aggressive.md`)
2. Concatenate core + tier content → write to `SOUL.md`

### Getting Them Started

Use the matrix below to decide what to recommend, then deliver it conversationally.

#### Recommendation Matrix

Use only strategies that are actually defined in the workspace. Do not invent unsupported products.

| Condition | Recommendation |
|-----------|----------------|
| Wallet unfunded or deployable capital < 25 USDC | No live strategy yet. Share the deposit address, suggest a practical starting amount, and keep the tone low-pressure. |
| Safe tier with 25-49 USDC | No passive yield strategy is deployable yet. Recommend funding to 50+ USDC for `byreal-idle-yield skill` or 200+ USDC for `byreal-stable-yield-farm skill`. `byreal-dca skill` should only be suggested if the user explicitly wants gradual market exposure despite the tier mismatch. `byreal-lp-copy-trading skill` remains a high-risk exception only. |
| Safe tier with 50-199 USDC | Default by goal: `byreal-idle-yield skill` for passive yield on parked funds only when the wallet has remained idle long enough to satisfy that skill's idle-time requirement; otherwise recommend waiting or using `byreal-dca skill` only if the user explicitly wants gradual market exposure. `byreal-stable-yield-farm skill` should be deferred until 200+ USDC. `byreal-lp-copy-trading skill` should only be presented as a high-risk exception with explicit mismatch warning and clear user approval. |
| Safe tier with >= 200 USDC | Default by goal: `byreal-idle-yield skill` for passive lending yield on parked capital only when the wallet has remained idle long enough to satisfy that skill's idle-time requirement, `byreal-stable-yield-farm skill` for lower-risk strategy yield, `byreal-dca skill` only if the user explicitly wants gradual market exposure. `byreal-lp-copy-trading skill` remains a high-risk exception only. |
| Balanced tier with 25-49 USDC | `byreal-lp-copy-trading skill` is the default candidate. `byreal-idle-yield skill` is not deployable yet at this size. `byreal-stable-yield-farm skill` is underfunded. |
| Balanced tier with 50-99 USDC | `byreal-lp-copy-trading skill` is the default candidate. `byreal-idle-yield skill` is a valid alternative only if the funds are expected to stay idle long enough to satisfy that skill's idle-time requirement. `byreal-stable-yield-farm skill` is underfunded. |
| Balanced tier with 100-199 USDC | Default by goal: `byreal-idle-yield skill` for passive parked funds only when those funds are expected to stay idle long enough to satisfy that skill's idle-time requirement, `byreal-dca skill` for accumulation, `byreal-lp-copy-trading skill` for active higher-risk execution. `byreal-stable-yield-farm skill` becomes available only if the user is comfortable funding up to the safer 200 USDC level. |
| Balanced tier with >= 200 USDC | Default by goal: `byreal-idle-yield skill` for passive parked funds only when those funds are expected to stay idle long enough to satisfy that skill's idle-time requirement, `byreal-stable-yield-farm skill` for lower-risk yield, `byreal-dca skill` for gradual accumulation, `byreal-lp-copy-trading skill` for active higher-risk execution. |
| Aggressive tier with 25-49 USDC | `byreal-lp-copy-trading skill` is the default candidate at this size. `byreal-idle-yield skill` is not deployable yet. |
| Aggressive tier with 50-99 USDC | `byreal-lp-copy-trading skill` is the default candidate at this size. `byreal-idle-yield skill` is a valid passive parking option only if the funds are expected to stay idle long enough to satisfy that skill's idle-time requirement. |
| Aggressive tier with >= 100 USDC | `byreal-lp-copy-trading skill` is the default active candidate. `byreal-dca skill` is a valid alternative for accumulation, and both `byreal-idle-yield skill` and `byreal-stable-yield-farm skill` are available if the user wants a lower-risk yield sleeve or parked-capital strategy, with `byreal-idle-yield skill` only recommended when funds are expected to stay idle long enough to satisfy that skill's idle-time requirement. |

### Recommendation Order

When multiple strategies are technically available, choose in this order:

1. Capital gate:
   - `< 25 USDC` → no live strategy
   - `25-49 USDC` → `byreal-lp-copy-trading skill` only
   - `50-99 USDC` → `byreal-lp-copy-trading skill`, or `byreal-idle-yield skill` only when funds are expected to remain idle long enough
   - `100-199 USDC` → `byreal-idle-yield skill`, `byreal-dca skill`, or `byreal-lp-copy-trading skill` depending on tier/goal, but only recommend `byreal-idle-yield skill` when funds are expected to remain idle long enough
   - `>= 200 USDC` → all current strategies can be considered
2. Goal match:
   - Passive yield / parked capital / low maintenance → `byreal-idle-yield skill`
   - Strategy yield / stable LP exposure → `byreal-stable-yield-farm skill`
   - Gradual accumulation / simple recurring exposure → `byreal-dca skill`
   - Active execution / higher-risk opportunity seeking → `byreal-lp-copy-trading skill`
3. Risk-tier override:
   - Safe → prefer `byreal-idle-yield skill`, then `byreal-stable-yield-farm skill`, then `byreal-dca skill`
   - Balanced → choose by user goal
   - Aggressive → prefer `byreal-lp-copy-trading skill`
4. If the best-fit strategy is unavailable at current capital, recommend the next-lower-risk valid option or advise funding up to the desired strategy threshold.

When recommending, always cover: why it matches their tier, why it matches their goal, minimum capital needed, how to size it for that tier, and the main risks. If no strategy fits, say so honestly — don't invent unsupported products.

Keep it concrete — what it does, roughly what it earns, why it fits them. If they want to skip or aren't sure, that's fine. No guilt, no urgency.

Example (funded, Balanced):
> With your balance, I'd pick based on what you want first: passive yield on idle funds, gradual accumulation, or a more active strategy. If you want active upside and accept the risk, LP Copy Trading can fit. If you want something steadier, I'd start with DCA or idle yield instead.

Example (not funded):
> Once you fund the wallet, I can suggest the best starting move for your tier. If you want a clean first step, starting with enough USDC for DCA or idle yield usually makes sense.

Example (Safe, funded):
> Your tier is about protecting capital first. So I'd lean toward idle yield for parked funds, or stable yield once the balance is large enough. I wouldn't default you into copy trading unless you explicitly want the extra risk.

### Getting to Know Them

After the financial stuff is settled, get to know them a bit — like a personal assistant's first day. Not a form, just a chat.

Before onboarding is complete, also confirm the notification channel fields required by `USER.md`:
- platform (`telegram`)
- handle / chat id
- preferred report cadence
- notify-on preference (`every_action`, `summary_only`, or `errors_only`)

Example:
> By the way — what should I call you? And what time zone are you in so I don't wake you up with reports at 3am?

> Anything else I should know? Some people like detailed reports, some just want a heads-up when something happens.

> Where should I send updates, and how often do you want them?

Record what you learn in `USER.md`, including the Notification Channel section. Don't force it — pick up what comes naturally, fill in the rest over time.

### Post-Onboarding Verification

Before deleting `BOOTSTRAP.md`, silently verify:

- `SOUL.md` exists and contains core + tier content (not just placeholders)
- `USER.md` exists with at minimum: name/alias, risk tier, timezone
- `USER.md` notification channel fields are filled
- Wallet address is present in USER.md (written by BOOT.md, not asked from user)
- `BOOT.md` startup checks pass (CLI installed, wallet accessible) — required by AGENTS.md §First Run and BOOTSTRAP.md
- User has received a first-run confirmation message — required by BOOTSTRAP.md

If any check fails, keep `BOOTSTRAP.md` in place and tell the user onboarding is incomplete — explain what's missing.
