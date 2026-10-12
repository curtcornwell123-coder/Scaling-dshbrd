# Marketing: what's next (on "resume")

## Done (interim)
- Ultimate Golf: 3D thumbnails `golf/thumbnails_3d/{hero,ranked,race}.png` (user picked these), icon `golf/icon.png`.
- Brainrot Heist / Merge A Egg / Cyber Swarm: 2D thumbnails `<game>/thumbnails/*.png`.
- Icons: `merge/icon.png`, `cyber/icon.png` (Brainrot Heist keeps its existing approved icon).
- Descriptions: `bios.md` (Merge A Egg, Cyber Swarm), `../chaos-golf/docs/Bio.md` (Ultimate Golf).

## Upload (Open Cloud, apis.roblox.com, x-api-key from the environment secret)
- Needs the API key permission `legacy-universe:manage` for each experience (writes return 403 without it).
- Thumbnail: `POST /legacy-game-internationalization/v1/game-thumbnails/games/{universeId}/language-codes/en/image`, multipart `request.files`.
- Icon: `POST /legacy-game-internationalization/v1/game-icon/games/{universeId}/language-codes/en`, multipart `request.files`.
- Verify by re-reading `GET /legacy-game-internationalization/v1/game-icon/games/{universeId}` (mutations can silently no-op without scope).
- Universe IDs: Merge A Egg 10770247652, Cyber Swarm 10769914606, Brainrot Heist 10769915066. Ultimate Golf: not published yet.

## On "resume"
1. Studio-quality 3D renders for Brainrot Heist, Merge A Egg, Cyber Swarm (render3d/scenes.py → run_all.sh,
   then overlay.py → `<game>/thumbnails_3d/`), plus golf skins/daily. 3D icons for each game (render3d/make_icon.py).
2. Promo videos for all four games from the 3D thumbnails (make_video.py, `--outro "Play <Game> now on Roblox"`).
3. Upload the finished set to each game, hero first.
