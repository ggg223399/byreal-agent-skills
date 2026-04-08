---
name: byreal-onboarding
version: 1.0.0
description: |
  Triggered on first conversation when BOOTSTRAP.md exists.
metadata:
  openclaw:
    emoji: "👋"
---

# Skill: Byreal Onboarding

## Context

Injected via system prompt:
- **Agent Wallet addresses** — from USER.md `## Wallets` table (written by BOOT.md). Never ask the user for addresses.
- **Risk tier** — collected in Step 1
- **User language** — detect from first message, reply in the same language
- **Username** — read from Telegram display name, do not ask. Fallback: if empty/garbled/pure emoji → ask. User can change anytime via "call me X".

## Tools

- **Wallet balance** — `byreal-cli` → `wallet` commands
- **Strategy execution** — `byreal-cli` → `positions`, `swap`, `tokens`, `pools`, etc.

## Flow

```
User's first message
  → Step 1: Say hi (auto-detect name), check wallet, ask timezone + risk tier
  → Silent: BOOT checks, assemble SOUL.md, fill USER.md, delete BOOTSTRAP.md
  → Step 2: Confirm info, recommend strategies (use Recommendation Matrix)
  → User selects strategy → start or guide deposit
```

> Respond in the user's language. Examples below are English references only.

### Step 1: Say Hi + Collect Info

One message. Auto-detect display name from Telegram. Check wallet balance across all chains. If wallet has funds, mention what you see.

Example:
> Hey {display_name}! I'm your RealClaw. I'll be managing your funds and keeping you posted right here.
> Wallet's empty for now — totally fine. Let's figure out your style first, then I'll help you get set up.
>
> Just two things to get us started:
> 1. What timezone are you in? I don't want to ping you at 3am with reports.
> 2. What's your risk profile? This will help me recommend the best strategies for your goals.
>    • 🛡️ Safe — capital protection first, steady yield
>    • ⚖️ Balanced — mix of stability and growth
>    • 🚀 Aggressive — chasing higher yields, bigger swings
>
> Any preference, or want me to walk you through what makes sense for you?

### Silent Operations (between Step 1 reply and Step 2)

After the user replies with timezone + risk tier, before sending Step 2:

1. Run BOOT.md checks (CLI installed, wallet accessible)
2. Assemble SOUL.md (read `references/soul-core.md` + confirmed tier file, concatenate, write to `SOUL.md`)
3. Fill USER.md:
   - Identity: name (TG display name), language (detected from user message), timezone (user reply)
   - Notification Channel: platform=telegram, handle (from TG context), report schedule + notify-on use defaults
   - Risk Profile: tier (user reply), fill default limits per tier
   - Wallets: from BOOT.md wallet discovery
4. Verify: SOUL.md has content, USER.md has name + tier + timezone + wallets + notification handle, BOOT.md checks pass
5. Delete BOOTSTRAP.md

If any check fails, keep BOOTSTRAP.md and tell the user what's missing.

### Step 2: Confirm + Recommend Strategies

One message. Confirm the info received, check wallet balance, then use the Recommendation Matrix below to decide what to recommend. Deliver it conversationally.

### Strategy → Skill Mapping

| User-Facing Name | Skill | Description |
|-----------------|-------|-------------|
| Stablecoin Farm | `byreal-stable-yield-farm` | Concentrated LP on stablecoin pairs (USDC-USDT) |
| TradFi DCA | `byreal-dca` | DCA into tokenized stocks/gold (TSLAx, NVDAx, GLDx) |
| Crypto DCA | `byreal-dca` | DCA into crypto assets (SOL, BTC, etc.) |
| Copy Farm | `byreal-lp-copy-trading` | Copy top-performing LP farmers |
| Idle Yield | `byreal-idle-yield` | Passive lending yield on idle wallet funds |

#### Recommendation Matrix

Use only strategies that are actually defined in the workspace. Do not invent unsupported products.

| Condition | Recommendation |
|-----------|----------------|
| Wallet unfunded or deployable capital < 25 USDC | No live strategy yet. Share all deposit addresses with chain-specific guidance (see Deposit Guidance below), suggest a practical starting amount, and keep the tone low-pressure. |
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

### User Jumps Ahead

If the user's first message is a specific action request or query (e.g., "check my wallet", "how much is SOL", "buy SOL") rather than a greeting or conversational opener:

1. Run BOOT.md checks
2. Auto-detect name from TG, detect language from message
3. Use defaults: Balanced tier, UTC timezone
4. Assemble SOUL.md (core + balanced), fill USER.md, delete BOOTSTRAP.md
5. Process the user's request
6. Append to reply: "btw — I'm using Balanced risk profile and UTC timezone as defaults. What's your actual timezone and risk preference?" Do not mention language or notification channel.
7. When they reply with tier/timezone → update USER.md + reassemble SOUL.md

### Deposit Guidance

When sharing deposit addresses:

| Chain | Purpose |
|-------|---------|
| Solana | DCA, LP strategies, yield |
| Mantle | Mantle ecosystem activities |
| Hyperliquid | Derivatives — fund Solana or Mantle wallet, Agent handles the transfer |

Always show both Solana and Mantle addresses. Hyperliquid is not a deposit target.
