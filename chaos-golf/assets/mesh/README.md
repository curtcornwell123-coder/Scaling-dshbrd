# Golf ball mesh

`golfball.obj`: 108-dimple golf ball, 482 vertices / 960 triangles. It is centred at the origin with a diameter of exactly 1.5 studs (bbox 1.5 x 1.5 x 1.5, the same as `Config.Ball.Diameter`). The file is Y-up, has outward CCW winding, and is watertight. It includes normals (soft cup shading) and spherical UVs. `golfball_preview.png` shows a software render of it.

## Import into Roblox

1. In Studio, open **Asset Manager → Import** (or **Home → Import 3D**) and pick `golfball.obj`.
2. In the 3D Importer, set **File Dimensions / Scale Unit = Stud** so the ball stays 1.5 studs. No materials or textures are needed. Click **Import**. The mesh is uploaded as an asset.
3. Copy the mesh id. Either select the imported MeshPart and copy its `MeshId`, or in Asset Manager → Meshes right-click `golfball` → **Copy Asset ID**.
4. Paste it into `src/shared/Config.luau`:
   ```lua
   MeshId = "rbxassetid://<id>",
   ```
   Keep `MeshScale = Vector3.new(1, 1, 1)`. `Skins.apply` already scales the mesh by `part.Size.X / 1.5`.
5. Delete the imported MeshPart from the place, because only the id is used. The mesh is visual only and physics still uses the ball Part's sphere.

## Regenerate

```sh
pip install numpy scipy pillow
python3 tools/gen_ball.py      # rewrites golfball.obj + golfball_preview.png and prints stats
```

You can tune `DEPTH`, `CUP_TILT_DEG` (cup shading strength) and `TARGET_TRIS` (max 1100) at the top of the script.
