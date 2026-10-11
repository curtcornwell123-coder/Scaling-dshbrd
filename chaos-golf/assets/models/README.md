# Exported models

Code-built pieces exported as Roblox model files (and uploaded as assets).

| Model | File | Roblox asset | Owner |
|---|---|---|---|
| Premium Marble Fountain (lobby centrepiece, running water) | `PremiumFountain.rbxm` / `.rbxmx` | 114362425242752 | Corny Games group |

Re-export after changing `src/server/World/Fountain.luau`:

    ROJO=<rojo> tools/export/export.sh <luau> <globalTypes.d.luau> "Lobby/Hub/Fountain" PremiumFountain assets/models

Insert in Studio: drag the `.rbxm` into the viewport, or Toolbox → My Models / Group models → "Premium Marble Fountain".
