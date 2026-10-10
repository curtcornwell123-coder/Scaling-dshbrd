# Chaos Golf — build progress

Resume point for the next session. Verify with `/tmp/claude-0/check.sh` (re-download tools if the container is new — see README "Development").

## Done
- Shared: Config, Skins (57, rarity auras), Cosmetics (Trails / Knockouts / Arrows), Crates (4 shop crates + Mythic + token), DailyRewards (14-day), Maps (12), Abilities (6), Ranks, Minigames, Net, UIKit (design system), ShopCatalog
- Server: Data (profiles, session lock, keys, login, cosmetics), Social, Economy, Activity, Zones, Tags, MythicStock, CreatorCodes, Monetization,
  BallService (physics, hits, knockouts), AbilityService, MatchService (Ranked/Classic/Race), Matchmaking, Voting, Shop, Daily, Leaderboards, Practice, Tutorial, Main
- Client: State, Hud (coin counter + world toasts), WorldFx, GolfController, MatchUi, Previews, Catalog, Terminals, Boards

## In progress / next
- Client: Prompts (personalized prompt text, invite kiosk, vote confirmation), Guide (first-join arrow)
- Integrate LobbyBuilder + CourseBuilder (background builders) and assets (icons, ball mesh)
- Zero diagnostics + rojo build, then docs: GDD.md, Monetization.md (price sheet), README setup
