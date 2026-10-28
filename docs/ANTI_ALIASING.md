# Anti-aliasing, resolution and sharpness plan

Written 28 Oct 2026 after the complaint "the game feels blurry when looking at places and low quality".
Code: `rendering/world_view.gd` (`_resize`, `_upscaler`, adaptive resolution), `rendering/graphics_quality.gd`
(`preset_scale`, `RENDER_BUDGET_MP`, `ADAPT_FLOOR`), `core/settings.gd` (`GFX_PRESETS`, `render_scale()`, the
`aa_rev` migration), `ui/settings_menu.gd` (Graphics tab), `world/sky/sky_controller.gd` (altitude blur / DOF).

## 1. Why it looked blurry (diagnosis)

Measured on the M4 MacBook, fullscreen 2940x1846 physical pixels (1470x923 points, 2x Retina), High preset,
`--capture-game --tour=village,vista,peaks`:

| Cause | Before | Effect |
|---|---|---|
| **Render scale was a fraction of the *logical* window** | High = 1.0 x logical = **0.5 of physical per axis**; Ultra 0.625; Low 0.325 | 3D rendered at 1347x846 (1.14 MP) and stretched 2.2x per axis to 2940x1846. This was the main blur. |
| Adaptive resolution floor | 0.55 of the preset, i.e. down to **0.275 of native** on High | Under load the image got even softer. |
| Upscaler | Automatic = MetalFX spatial on Mac | Godot exposes no sharpening for MetalFX spatial, so the "Sharpness" slider did nothing on Mac. |
| TAA at that low resolution | TAA on (High/Ultra), no sharpening after it | TAA's history blend softens; nothing restored the detail. |
| Mountain distance blur (`altitude_blur`) | **on** by default | Far DOF from 700 m (260 m at altitude) on every outdoor view with altitude > 0.03. |
| Mip bias | 0 on High | Godot already adds log2(scale) below native; fine, but TAA can take a sharper mip. |
| Rain/snow depth haze (`DepthEffects.haze`) | only during precipitation | Intentional weather look; not part of the clear-weather blur. Left as is. |
| Depth of field option | off by default | Not a cause. |

Before crop (`build/agent/before/vista.png`, full-res crop): houses, stones and grass are visibly smeared;
roof edges are a 2-pixel ramp.

## 2. What Godot 4.7 offers (Forward+, Metal)

| Option | What it does | Cost (M4, this game) | Notes |
|---|---|---|---|
| FXAA (`screen_space_aa`) | Post-process edge blur on luma contrast | ~0.2 ms | Softens textures as well as edges. |
| SMAA 1x (`SCREEN_SPACE_AA_SMAA`, new in 4.5) | Morphological edge AA with pattern search | ~0.5 ms | Sharper than FXAA, no temporal stability (foliage still crawls). |
| TAA (`use_taa`) | Jittered projection + history reprojection | ~1 ms | Best for shimmering grass/leaves and specular; softens; ghosts on things without motion vectors (particles, water surface, scrolling UVs). |
| MSAA 2x/4x (`msaa_3d`) | Multisampled geometry edges | 2-6 ms in Forward+ | Only geometry edges; enables alpha-to-coverage on alpha-scissor materials. Does nothing for shader/specular aliasing. |
| FSR 1 (`SCALING_3D_MODE_FSR`) | Spatial EASU upscale + **RCAS sharpening** (`fsr_sharpness`, 0 = max .. 2 = off) | < 1 ms | The only upscaler sharpening Godot exposes. Disabled at scale >= 1.0. |
| MetalFX spatial | Apple's spatial upscaler | < 1 ms | No sharpening control; looked softer. |
| FSR 2 / MetalFX temporal | Temporal upscalers (also do AA) | measured ~15 ms/frame more than spatial at 2940x1652 (earlier session) | Best reconstruction, too expensive on this GPU class for a default. |
| Automatic mip bias | Godot adds `log2(scaling_3d_scale)` below native | free | `texture_mipmap_bias` is added on top. |
| Screen-space roughness limiter | Raises roughness where normals vary per pixel (specular AA) | ~0.1 ms | Already on in `project.godot`. |
| Alpha antialiasing (`ALPHA_ANTIALIASING_EDGE`) | Alpha-to-coverage on alpha-scissor materials | free; needs MSAA to show | Without MSAA it behaves exactly like the scissor. |

## 3. What each preset does now

The 3D resolution is now a fraction of the window's **physical** pixels (100% = native, also on Retina). A preset asks
for a pixel budget with a floor (`GraphicsQuality.preset_scale`): `scale = clamp(sqrt(budget / window_MP), floor, 1)`.

| Preset | Budget / floor | 1080p | 2940x1846 Mac | 4K | AA | Mip bias (extra) | Adaptive floor |
|---|---|---|---|---|---|---|---|
| Low | 0.8 MP / 0.40 | 0.62 | 0.40 | 0.40 | FXAA | +0.5 | 0.60 x preset |
| Medium | 1.3 MP / 0.50 | 0.79 | 0.50 | 0.50 | **SMAA** | 0 | 0.65 x preset |
| High | 2.2 MP / 0.60 | **1.0** | **0.64** | 0.60 | TAA + FSR 1 RCAS | -0.5 (-0.25, -0.25 for TAA) | **0.75** x preset |
| Ultra | 4.0 MP / 0.75 | 1.0 | 0.86 | 0.75 | TAA + FSR 1 RCAS | -0.75 | 0.80 x preset |

- **Upscaler Automatic = FSR 1 everywhere** (was MetalFX spatial on Mac) so the Sharpness slider works.
- **Sharpness default 0.8** (RCAS 0.4 stops; was 0.5 = 1.0 stop, and ignored on Mac).
- **Sharpen at native**: when the scale reaches 1.0 with TAA and the Automatic upscaler, the view renders at 99% with FSR 1
  so RCAS still runs after TAA (Godot has no stand-alone sharpen pass). Near-identity resample, < 0.5 ms.
- **Ultra keeps TAA, no MSAA**: at 0.86-1.0 of native the resolution is the AA; MSAA would add 2-6 ms for geometry edges
  that TAA already covers, and does nothing for grass/specular shimmer. MSAA stays a manual choice (and then leaves get
  alpha-to-coverage, see below).
- **Mountain distance blur is off by default.** Existing settings files are migrated once (`aa_rev` < 1: altitude blur
  off, sharpness raised to at least 0.8). The option still exists.
- The settings keys are unchanged (`antialiasing`, `upscaler`, `sharpness`, `render_scale`, `adaptive_resolution`,
  `texture_quality`, `altitude_blur`); `antialiasing` gained value **5 = SMAA** (appended, so 0-4 keep their meaning).
  A forced `render_scale` (50%..100% in the menu) now means a share of native pixels.

## 4. Measurements (M4, 6 agents sharing the machine — fps is noisy)

| Run | Output | 3D viewport | village | vista | peaks* |
|---|---|---|---|---|---|
| before (main f3e319e) | 2940x1846 | 1347x846 MetalFX spatial (1.14 MP) | 32 fps | 36 fps | 58 fps |
| budget 2.6 MP / floor 0.67 (rejected) | 2940x1846 | 1974x1239 FSR 1 (2.45 MP) | 27 fps | 26 fps | 30 fps |
| final (2.2 MP / 0.6) | 2940x1652 | 1603x901 FSR 1 (adaptive dropped to x0.81 under machine load) | 22 fps | 25 fps | 25 fps |

\* the peaks stop landed at different spots (altitude 172 m before, 57-61 m after; 0.39 M vs 2.6 M primitives), not comparable.

The final run rendered *fewer* pixels than the 2.6 MP run and was still slower: other agents' headless test runs were
using the CPU, and `process` time (which includes the Metal GPU wait) tracked the frame time. **Re-measure on an idle
machine** (same command, `--gfx=adaptive_resolution:false` to pin the scale) before tuning the budgets further. If High
costs more than ~5 ms over the old preset on an idle M4, lower `RENDER_BUDGET_MP[2]` to 1.8 (scale 0.58 on the Mac).

Looked at (full-resolution crops, `build/agent/crop.py`): `build/agent/before/vista.png` vs `build/agent/after1/vista.png`
and `after2/vista.png`; `before/village.png` vs `after1/village.png`. After: stone and timber textures resolve, grass
blades and roof edges are crisp, leaf cards still render correctly with the alpha-scissor change.

Capture command (`--gfx=` is new: any graphics option for one run; the report line now records TAA/MSAA/SMAA state,
RCAS sharpness, mip bias and the adaptive factor):

```
burn_slot.sh gpu caffeinate -d -u godot --path . --fullscreen -- --capture-game=$PWD/build/agent/shots \
    --tour=village,vista,peaks --quality=2 --no-update --data-dir=$PWD/build/agent/gpu-user \
    [--gfx=antialiasing:5,upscaler:4,sharpness:0.5,adaptive_resolution:false]
```

`caffeinate -d -u` matters: with the display asleep the window is 0x0 and every PNG is 2x2 pixels.

## 5. Known issues

- **Specular aliasing** (wet stone, water glints, metal): roughness limiter is on with Godot's defaults
  (amount 0.25, limit 0.18). Could go to 0.4 / 0.25 if sparkle remains; costs nothing.
- **Foliage and grass shimmer** without TAA (Low/Medium): leaf cards are alpha-tested; FXAA/SMAA cannot stabilise sub-pixel
  blades. Mip-compensated alpha (`tex.a * (1 + mip * 0.22)`) keeps coverage at distance.
- **Thin geometry** (fence rails, lantern posts, sword in hand): crawls under FXAA/SMAA at low scales; TAA fixes most of it.
- **TAA ghosting**: particles (rain, embers), the water surface and anything moved without motion vectors (vertex wind in
  world space is fine, flipbooks are not) trail slightly. The viewmodel is drawn in the same pass and can smear on fast
  swings.
- **Adaptive resolution misreads CPU load as GPU load** briefly: under heavy CPU load it dropped to x0.81 for no gain
  before its CPU-bound check kicked in. The new floor (0.75 on High) caps the damage.
- MetalFX temporal / FSR 2 cost ~15 ms/frame more at this output (earlier measurement); worth re-measuring on Godot 4.7.

## 6. Done in this pass

1. Render scale in native pixels with per-preset budgets and floors; adaptive floor per preset.
2. Automatic upscaler = FSR 1 (RCAS sharpening works on Mac); sharpness 0.8 by default; sharpen-at-native path.
3. Presets: Low FXAA, Medium SMAA, High/Ultra TAA; extra negative mip bias with TAA; anisotropic filtering was already
   applied per texture_quality (2x..16x) and every terrain/voxel/architecture/arena/bark/leaf sampler uses
   `filter_linear_mipmap_anisotropic`; `flora_rock.gdshader` was the exception and now uses it too.
4. Mountain distance blur off by default, with a one-time migration for existing settings.
5. Leaf cards (`flora_leaves.gdshader`) use `ALPHA_SCISSOR_THRESHOLD` + `ALPHA_ANTIALIASING_EDGE` (alpha-to-coverage under MSAA).
6. Unit tests: `test_graphics_settings` (render scale is a native fraction, presets pick FXAA/SMAA/TAA, defaults).

## 7. Next steps (in order of value)

1. **Idle-machine perf pass** of High/Ultra budgets (see section 4), and a third-person + night + forest tour.
2. **CAS sharpen compositor effect** (one compute pass after tonemap) to replace the 99%-FSR trick at native and to
   sharpen SMAA/FXAA presets too.
3. Roughness limiter tuning (amount 0.4) and specular AA in custom shaders that write `ROUGHNESS` directly
   (`terrain`, `voxel`, `architecture`): widen roughness by `fwidth(NORMAL)` (Kaplanyan-style) where the limiter does not reach.
4. Alpha-to-coverage for any other alpha-tested material (sea plants, ambient critters use `discard`).
5. TAA ghosting: give particles and the water surface `render_mode` / motion-vector handling, or exclude them from the
   history (draw after TAA via a separate pass) if the ghosting is noticeable.
6. Re-test FSR 2 and MetalFX temporal on 4.7 at 0.6-0.67 scale; if the cost is now < 3 ms, offer "High (temporal)"
   or make it Ultra's default.
7. LOD/mips: check the horizon (`distant_land.gdshader`) mip selection at 1-4 km; its albedo array may want a +0.5 bias
   to stop sparkle at the 4.2 km far plane.
