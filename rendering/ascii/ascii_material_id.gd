class_name AsciiMaterialId
extends RefCounted
## Material classes the ASCII pass understands, and how they travel through the
## G-buffer.
##
## Godot's Forward+ depth prepass writes `normal_roughness` (RGBA8) where the
## alpha byte is `round(roughness * 127)`, flipped to `255 - x` for dynamic
## instances (see scene_forward_clustered.glsl, MODE_RENDER_NORMAL_ROUGHNESS).
## Every world material quantises its roughness to 16 levels and stores the
## material ID in the low 3 bits of that 7-bit value. The roughness change is
## at most 1/30, invisible once the scene is drawn as glyphs, and it costs no
## extra render pass. The screen-space roughness limiter must stay disabled
## (project.godot) because it would rewrite roughness per pixel.
##
## This file is the GDScript mirror of
## res://rendering/materials/ascii_material.gdshaderinc and of the decode in
## ascii_prep.glsl; tests/unit/test_material_id.gd keeps the three in step.

const SOLID := 0     ## stone, creatures, the dragon: dense ramp
const FOLIAGE := 1   ## grass, bushes, trees: directional strokes
const LIQUID := 2    ## water, puddles: animated ~ - =
const STREAK := 3    ## rain: slanted strokes following the streak
const GROUND := 4    ## terrain, floors: lighter, sparser ramp
const EMISSIVE := 5  ## opaque glowing surfaces: passed through, not converted
const CLOTH := 6     ## banners, cloaks: dense ramp
const DEFAULT := 7   ## anything that never chose an ID (roughness 1.0 lands here)
const SKY := 8       ## not a material: depth == far plane

const NAMES := ["solid", "foliage", "liquid", "streak", "ground", "emissive", "cloth", "default", "sky"]

const LEVELS := 16


## Roughness value a material must output so the ASCII pass reads `id`.
static func encode_roughness(roughness: float, id: int) -> float:
	var level := clampf(floorf(roughness * float(LEVELS - 1) + 0.5), 0.0, float(LEVELS - 1))
	return (level * 8.0 + float(id)) / 127.0


## The byte Godot writes to normal_roughness.a for a given shader roughness.
static func stored_byte(shader_roughness: float, dynamic: bool) -> int:
	var w := shader_roughness * (127.0 / 255.0)
	if dynamic:
		w = 1.0 - w
	return clampi(roundi(w * 255.0), 0, 255)


## Material ID recovered from a normal_roughness alpha byte.
static func decode_byte(stored: int) -> int:
	var w := stored
	if w > 127:
		w = 255 - w
	return w & 7


## Roughness (0..1) recovered from a normal_roughness alpha byte.
static func decode_roughness(stored: int) -> float:
	var w := stored
	if w > 127:
		w = 255 - w
	return float(w >> 3) / float(LEVELS - 1)
