# Credits

**Burn** — game design, code, world generation, models, shaders, sound and music are original work
created for this project. Everything visible and audible is generated procedurally at runtime
(terrain, structures, creatures, glyph atlas, sound effects, ambience and music).

## Third-party assets

| Asset | Source | Licence | Used for |
|---|---|---|---|
| JetBrains Mono (Regular, Bold) | https://github.com/JetBrains/JetBrainsMono | SIL Open Font License 1.1 (`assets/fonts/OFL.txt`) | Glyph atlas, UI text |
| Cinzel (variable) | https://github.com/NDISCOVER/Cinzel via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/Cinzel-OFL.txt`) | Titles, banners |

## Techniques

| Work | Author | Licence | Notes |
|---|---|---|---|
| AcerolaFX ASCII shader | Garrett Gunnell | MIT | The edge-direction method (depth/normal edges, Sobel, per-cell direction voting) in `rendering/ascii/shaders/ascii_edges.glsl` / `ascii_sobel.glsl` / `ascii_cells.glsl` is adapted from `AcerolaFX_ASCII.fx`. No code or textures were copied verbatim; the glyph atlas is generated from JetBrains Mono at runtime. |

## Engine

Godot Engine 4.7 — MIT licence, © Godot Engine contributors.
