# Mega Blox Adventure (Roblox Studio — ServerScriptService)

A complete Roblox game delivered as **one server Script**. Paste it into
`ServerScriptService` in Roblox Studio and press Play — the script builds the
whole world, shop, quests, events, and data saving by itself.

## File

| File | Paste into | Type |
|---|---|---|
| [`ServerScriptService/MainServer.luau`](ServerScriptService/MainServer.luau) | `ServerScriptService`, named `MainServer` | `Script` (not LocalScript) |

## Install (60 seconds)

1. Open your place in Roblox Studio.
2. In the Explorer, select **ServerScriptService** → **Insert → Script**,
   rename it to `MainServer`.
3. Open [`ServerScriptService/MainServer.luau`](ServerScriptService/MainServer.luau),
   copy everything, paste over the Script contents.
4. (Optional, for data saving in Studio) Game Settings → Security →
   enable **Studio Access to API Services**.
5. Press **Play**. The map, shop, coins, dummies, chasers, quests and events
   all appear automatically.

## What's in the game

- **25-stage obby** with checkpoints, lava, stairs, beams, moving and fading
  platforms, plus a gold **Win pad** (500 coins + fireworks per win).
- **Data saving** — Coins, Gems, Wins, Rebirths, Level, XP, stages, quest and
  streak progress; autosaves every 2 minutes + on leave + on shutdown.
- **leaderstats**: Coins, Gems, Wins, Rebirths, Level.
- **XP / levels** (up to 100), coin rewards per level.
- **Rebirth** pad (+50% coin earnings per rebirth, stacking).
- **Shop** — Speed Coil, Gravity Coil, Swift Sword, Heal Potion.
  Buy via green pads at spawn or by typing `/shop`.
- **Coin orbs** (24, respawning), **training dummies**, monster **arena** with
  chaser enemies, **VIP lounge**, 5 **quests**, 7-day **login streak**.
- **Events** — scheduled double-coins, day/night cycle, rotating tips.
- **Admin chat commands** — `/help` lists them all (`/coins`, `/gems`,
  `/setstage`, `/give`, `/tp`, `/bring`, `/kill`, `/kick`, `/event coins`,
  `/day`, `/night`, `/announce`, `/shutdown`). Add names/UserIds in `CONFIG.Admins`
  (Studio testers are admins automatically).
- **Anti-exploit** — speed/jump sanity checks with warnings and kick threshold.

## Tune it

Everything lives in the `CONFIG` table at the top of the script: prices,
rewards, stage count, enemy stats, event timers, gamepass IDs, admins.
