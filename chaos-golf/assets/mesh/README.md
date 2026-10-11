# Golf ball mesh

`golfball.obj` / `golfball.fbx` is the premium tour ball every skin uses. It has 252 round dimples on an icosahedral layout (12 five-neighbour and 240 six-neighbour dimples), 7,502 vertices and 15,000 triangles, under the 20k import limit. It is centred at the origin with a diameter of exactly 1.5 studs (`Config.Ball.Diameter`), Y-up, with outward CCW faces, and it is watertight.

- **Dimples:** each one is a round spherical cup on two rings of points. A flat land band runs out to its Voronoi cell edge, so neighbours are split by narrow ridges with small triangular land patches at the corners, like a real ball.
- **Normals:** analytic. Inside a dimple they follow the cup, on the land they are radial, and they split at the rim so every dimple has a crisp edge. Custom normals survive the FBX export.
- **UVs:** cube projection per dimple cell, so part materials (Foil, Glass, Ice) read evenly with no pole pinching.

`golfball_preview.png` is a software render.

## Uploaded copies

| Owner | Asset id | Used when |
|---|---|---|
| Corny Games group (187537803) | `rbxassetid://108440465413524` | the game belongs to the group |
| Owner's account (469657246) | `rbxassetid://140361458276465` | unpublished files / personal places |

Both ids are in `Config.Ball.MeshIds`. At boot, `BallService` loads the right copy first and falls back to the other. It publishes the loaded `BallMeshId` and the native `BallMeshSize` on ReplicatedStorage, and `Skins.fitMesh` scales the mesh to any ball size.

## Printing

Logos, numbers, lines and stripes are built from tiny tangent plates in `src/shared/BallPrints.luau`, not baked into the mesh, so every skin can carry its own design (`Skins.design`).

## Regenerate / re-upload

```sh
python3 tools/gen_ball.py      # rewrites golfball.obj + golfball_preview.png, prints stats
```

Then convert to FBX with Blender, importing the OBJ with forward `-Z` and up `Y`, and exporting FBX with `mesh_smooth_type='OFF'` so custom normals are kept. Upload it through Open Cloud as `assetType: "Mesh"` for both owners, and paste the new ids into `Config.Ball.MeshIds`.

## Showcase renders

```sh
tests/boot/dump_balls.sh <luau> <globalTypes.d.luau> balls.txt
python tools/render_balls.py balls.txt --sheet                 # docs/renders/balls/collection_*.png
python tools/render_balls.py balls.txt --only corny_studio --views three,back
```
