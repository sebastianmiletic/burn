# Credits

**Burn** — game design, code, world generation, models, shaders, sound and music are original work
created for this project. Everything visible and audible is generated procedurally at runtime
(terrain, structures, creatures, glyph atlas, sound effects, ambience and music).

## Third-party assets

| Asset | Source | Licence | Used for |
|---|---|---|---|
| JetBrains Mono (Regular, Bold) | https://github.com/JetBrains/JetBrainsMono | SIL Open Font License 1.1 (`assets/fonts/OFL.txt`) | Glyph atlas, UI text |
| Cinzel (variable) | https://github.com/NDISCOVER/Cinzel via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/Cinzel-OFL.txt`) | Titles, banners |
| Jolcham Oak Bark 01, Pine Bark, Bark Willow 02, Rock Boulder Dry (diffuse + GL normal, downscaled to 512 px) | Poly Haven, https://polyhaven.com/textures | CC0 1.0 | Tree trunks, fallen logs, boulders and pebbles (`world/flora/textures/*_bark_*.jpg`, `rock_*.jpg`) |

The leaf atlas (`world/flora/textures/leaf_atlas*.png`) is painted procedurally by
`world/flora/tools/bake_leaf_atlas.gd`.

## Techniques

| Work | Author | Licence | Notes |
|---|---|---|---|
| AcerolaFX ASCII shader | Garrett Gunnell | MIT | The edge-direction method (depth/normal edges, Sobel, per-cell direction voting) in `rendering/ascii/shaders/ascii_edges.glsl` / `ascii_sobel.glsl` / `ascii_cells.glsl` is adapted from `AcerolaFX_ASCII.fx`. No code or textures were copied verbatim; the glyph atlas is generated from JetBrains Mono at runtime. |

## Engine

Godot Engine 4.7 — MIT licence, © Godot Engine contributors.
