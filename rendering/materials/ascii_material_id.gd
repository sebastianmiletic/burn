class_name AsciiMaterialId
extends RefCounted
## Legacy material class tags. The ASCII renderer that read them is gone; the
## constants remain only so existing material code keeps compiling, and
## `encode_roughness` now returns the roughness unchanged (no quantisation, so
## materials get their full specular precision). New code should not use this;
## it can be deleted once no caller passes a class id.

const SOLID := 0
const FOLIAGE := 1
const LIQUID := 2
const STREAK := 3
const GROUND := 4
const EMISSIVE := 5
const CLOTH := 6
const DEFAULT := 7


## The roughness a material should use (the class id is ignored).
static func encode_roughness(roughness: float, _id: int) -> float:
	return clampf(roughness, 0.0, 1.0)
