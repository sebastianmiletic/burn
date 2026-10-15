# Credits

**Burn** — game design, code, world generation, models, shaders, sound and music are original work
created for this project. Everything visible is generated procedurally at runtime (terrain, structures,
creatures, glyph atlas); music is fully synthesised, and sound effects and ambience are synthesised
at startup, layered with a small set of public-domain (CC0) recordings listed below.

## Third-party assets

| Asset | Source | Licence | Used for |
|---|---|---|---|
| Impact Sounds (Kenney) | https://kenney.nl/assets/impact-sounds | CC0 1.0 (`audio/samples/kenney_impact/License.txt`) | Footsteps (grass, snow, wood, stone), punches, mining, wood / metal / glass impacts — layered into footsteps, hits, mining and breaking sounds |
| RPG Audio (Kenney) | https://kenney.nl/assets/rpg-audio | CC0 1.0 (`audio/samples/kenney_rpg/License.txt`) | Footsteps (dirt), cloth, leather, belts, blade draw, chop, creaks, doors, latches, coins |
| Park Ambiences — river (thimras) | https://opengameart.org/content/park-ambiences | CC0 1.0 | 30 s excerpt (high-passed, `audio/samples/field/river_thimras.ogg`) for the stream and waterfall beds |
| Crickets Ambient Noise (wolfgang) | https://opengameart.org/content/crickets-ambient-noise-loopable | CC0 1.0 | Night crickets bed (`audio/samples/field/crickets_wolfgang.ogg`) |
| JetBrains Mono (Regular, Bold) | https://github.com/JetBrains/JetBrainsMono | SIL Open Font License 1.1 (`assets/fonts/OFL.txt`) | Glyph atlas, UI text |
| Cinzel (variable) | https://github.com/NDISCOVER/Cinzel via Google Fonts | SIL Open Font License 1.1 (`assets/fonts/Cinzel-OFL.txt`) | Titles, banners |
| Patterned Clay Plaster, Rough Wood, Old Planks 02, Rustic Stone Wall, Rustic Stone Wall 02, Reed Roof 04, Roof Slates 02 and 03, Rust Coarse 01, Rough Linen, Stone Pathway 02, Brown Planks 09 (diffuse, GL normal, roughness, AO; 1k, packed into texture arrays) | Poly Haven, https://polyhaven.com/textures | CC0 1.0 | Modelled buildings, villages and ruins (`assets/architecture/arch_albedo.jpg`, `arch_normal.webp`; packing script `tools/textures/pack_architecture.py`) |
| Jolcham Oak Bark 01, Pine Bark, Bark Willow 02, Rock Boulder Dry (diffuse + GL normal, downscaled to 512 px) | Poly Haven, https://polyhaven.com/textures | CC0 1.0 | Tree trunks, fallen logs, boulders and pebbles (`world/flora/textures/*_bark_*.jpg`, `rock_*.jpg`) |

| Marble Cliff 01, Dark Rock 02, Gray Rocks, Cliff Side (diffuse, GL normal, roughness, displacement; 1k) | Poly Haven, https://polyhaven.com/textures | CC0 1.0 | Terrain layers for mountain rock faces, basalt, scree and the red mesa cliffs (row 7 of `assets/terrain/terrain_albedo.jpg` / `terrain_normal.webp`) |

The leaf atlas (`world/flora/textures/leaf_atlas*.png`) is painted procedurally by
`world/flora/tools/bake_leaf_atlas.gd`.

## Techniques

| Work | Author | Licence | Notes |
|---|---|---|---|
| AcerolaFX ASCII shader | Garrett Gunnell | MIT | The edge-direction method (depth/normal edges, Sobel, per-cell direction voting) in `rendering/ascii/shaders/ascii_edges.glsl` / `ascii_sobel.glsl` / `ascii_cells.glsl` is adapted from `AcerolaFX_ASCII.fx`. No code or textures were copied verbatim; the glyph atlas is generated from JetBrains Mono at runtime. |

## Engine

Godot Engine 4.7 — MIT licence, © Godot Engine contributors.
