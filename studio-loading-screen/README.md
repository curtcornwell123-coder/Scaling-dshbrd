# Corny Games loading screen

One loading screen for every Corny Games experience: the studio logo, "Corny presents...", then the
game's own icon and name (read from Roblox automatically) with a live loading bar and a Skip button.

## Add it to a game (about 30 seconds)

1. Open the game in Studio.
2. In the Explorer, right-click **ReplicatedFirst** → **Insert from File...** → pick `CornyLoadingScreen.rbxmx`.
3. Publish (File → Publish to Roblox).

Nothing to edit per game. The logo image is uploaded twice (Roblox only loads an image in games owned by
the same account or group), and the script picks the right copy from the game's owner:

| Owner | Logo asset |
|---|---|
| Your account (469657246) | `rbxassetid://85146512996278` |
| Group 187537803 | `rbxassetid://71441156027815` |

Games owned by anyone else fall back to a clean "CORNY GAMES" wordmark.

## Files

- `LoadingScreen.client.luau`: the script (source of truth)
- `CornyLoadingScreen.rbxmx`: the same script as a Studio model (rebuild: `rojo build default.project.json -o CornyLoadingScreen.rbxmx`)
- `corny_games_logo.png`: the high-res transparent logo (regenerate: `python3 gen_logo.py`)
