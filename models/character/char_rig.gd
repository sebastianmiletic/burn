class_name CharRig
extends RefCounted
## Bone layout of every humanoid. Rest rotations are identity, so a bone's pose
## rotation is an Euler angle in its parent's frame (x pitches a limb forward,
## z rolls it outward, like the old joint nodes). Positions are in "body units":
## a 1.8 m human; the model scales the whole skeleton by height / 1.8.
## Models face -Z, +X is the character's right.

enum { HIPS, SPINE, CHEST, NECK, HEAD, JAW,
	CLAV_L, UARM_L, FARM_L, HAND_L, FING_L,
	CLAV_R, UARM_R, FARM_R, HAND_R, FING_R,
	THIGH_L, SHIN_L, FOOT_L, TOE_L,
	THIGH_R, SHIN_R, FOOT_R, TOE_R,
	BODY_BONES }

const NAMES := ["hips", "spine", "chest", "neck", "head", "jaw",
	"clav_l", "uarm_l", "farm_l", "hand_l", "fing_l",
	"clav_r", "uarm_r", "farm_r", "hand_r", "fing_r",
	"thigh_l", "shin_l", "foot_l", "toe_l",
	"thigh_r", "shin_r", "foot_r", "toe_r"]

const PARENTS := [-1, HIPS, SPINE, CHEST, NECK, HEAD,
	CHEST, CLAV_L, UARM_L, FARM_L, HAND_L,
	CHEST, CLAV_R, UARM_R, FARM_R, HAND_R,
	HIPS, THIGH_L, SHIN_L, FOOT_L,
	HIPS, THIGH_R, SHIN_R, FOOT_R]

## Cloak simulation grid (bones appended after the body bones when a cloak exists).
const CLOAK_COLS := 5
const CLOAK_ROWS := 5


## Proportions read from a style: bulk (width), shoulder width, hip width, arm length.
static func proportions(style: Dictionary) -> Dictionary:
	var b := float(style.get("bulk", 1.0))
	var fem := 1.0 if style.get("female", false) else 0.0
	var gaunt := bool(style.get("gaunt", false))
	return {
		"bulk": b,
		"fem": fem,
		"gaunt": gaunt,
		"muscle": float(style.get("muscle", 0.0)),
		"belly": float(style.get("belly", 0.0)),
		"arm": float(style.get("arm_length", 1.0)),
		"shoulder": 0.19 * b * lerpf(1.0, 0.88, fem) * (0.94 if gaunt else 1.0),
		"hip": 0.092 * b * lerpf(1.0, 1.08, fem),
		"limb": (0.72 if gaunt else 1.0) * lerpf(1.0, 0.9, fem),
		"skeleton": bool(style.get("skeleton", false)),
	}


## Bind-pose (global, body units) position of every body bone.
static func rest_positions(pr: Dictionary) -> PackedVector3Array:
	var sw: float = pr["shoulder"]
	var hw: float = pr["hip"]
	var al: float = pr["arm"]
	var p := PackedVector3Array()
	p.resize(BODY_BONES)
	p[HIPS] = Vector3(0, 0.97, 0)
	p[SPINE] = Vector3(0, 1.09, 0.005)
	p[CHEST] = Vector3(0, 1.27, 0.01)
	p[NECK] = Vector3(0, 1.5, 0.0)
	p[HEAD] = Vector3(0, 1.615, -0.005)
	p[JAW] = Vector3(0, 1.66, -0.015)
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 5
		p[CLAV_L + o] = Vector3(sg * 0.025, 1.455, -0.005)
		var sh := Vector3(sg * sw, 1.44, 0.0)
		p[UARM_L + o] = sh
		var el := sh + Vector3(sg * 0.02, -0.285 * al, 0.012)
		p[FARM_L + o] = el
		var wr := el + Vector3(sg * 0.016, -0.255 * al, -0.008)
		p[HAND_L + o] = wr
		p[FING_L + o] = wr + Vector3(sg * 0.004, -0.088 * al, -0.004)
	for side in 2:
		var sg := -1.0 if side == 0 else 1.0
		var o := 0 if side == 0 else 4
		p[THIGH_L + o] = Vector3(sg * hw, 0.915, 0.0)
		p[SHIN_L + o] = Vector3(sg * (hw - 0.004), 0.5, -0.006)
		p[FOOT_L + o] = Vector3(sg * (hw - 0.004), 0.085, 0.01)
		p[TOE_L + o] = Vector3(sg * (hw - 0.002), 0.022, -0.12)
	return p


static func thigh_len(rest: PackedVector3Array) -> float:
	return rest[SHIN_L].distance_to(rest[THIGH_L])


static func shin_len(rest: PackedVector3Array) -> float:
	return rest[FOOT_L].distance_to(rest[SHIN_L])
