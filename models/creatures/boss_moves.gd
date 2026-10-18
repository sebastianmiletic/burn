extends RefCounted
## Choreography for the humanoid bosses' bespoke moves (BossHumanoid.moves).
##
## A move is a dictionary of keyframe tracks over the action's progress p
## (0..1); BossHumanoid._pose_move() plays it instead of the shared
## HumanoidModel swings. Every builder takes `i`, the fraction of the action at
## which the blow lands, so the strike meets the telegraph exactly when the
## boss passes `duration = telegraph / i`. Tracks:
##   <bone int>      [[p, Vector3 euler]...]  absolute target, blended by the action weight
##   "add"           {bone: [[p, Vector3]...]} added on top of the pose
##   "hips"          [[p, Vector3]...]  pelvis offset (rest space, body units)
##   "rot"           [[p, Vector3]...]  pelvis rotation added (lean, twist)
##   "turn"          [[p, float]...]    whole-body turns about Y (spins), in turns
##   "foot_l/_r"     [[p, Vector3]...]  foot IK target offsets (steps, stomps, jumps)
##   "grip_r/_l"     [[p, wrist, item dir, finger dir]...] exact hand placement (IK)
##   "grip_w"        [[p, float]...]    weight of those grips
##   "two_hand"      true: the off hand rides the weapon's grip
##   "fing"          [[p, float]...]    finger curl (both hands)
##   "jaw"           [[p, float]...]    jaw open
##   "swing"         [from, to]         weapon trail window
## Euler conventions (CharRig): x pitches a limb forward (arms) / leans the
## spine back; y turns to the character's left; z rolls the right arm out
## (the left arm out with -z). Models face -Z, +X is the character's right.

const R := preload("res://models/character/char_rig.gd")

const ARM_R := Vector3(0.35, 0.0, 0.12)
const ARM_L := Vector3(0.35, 0.0, -0.12)
const ZERO := Vector3.ZERO


## Vector3 keyframes with smoothstep easing between keys.
static func kv(t: float, points: Array) -> Vector3:
	if t <= float(points[0][0]):
		return points[0][1]
	for k in range(points.size() - 1):
		var a: Array = points[k]
		var b: Array = points[k + 1]
		if t <= float(b[0]):
			var f := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			f = f * f * (3.0 - 2.0 * f)
			return (a[1] as Vector3).lerp(b[1], f)
	return points[points.size() - 1][1]


static func kf(t: float, points: Array) -> float:
	if t <= float(points[0][0]):
		return points[0][1]
	for k in range(points.size() - 1):
		var a: Array = points[k]
		var b: Array = points[k + 1]
		if t <= float(b[0]):
			var f := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
			f = f * f * (3.0 - 2.0 * f)
			return lerpf(a[1], b[1], f)
	return points[points.size() - 1][1]


static func _c(v: float) -> float:
	return clampf(v, 0.0, 1.0)


# --- Weapon blows -------------------------------------------------------------------------

## Two-handed overhead chop: gather, lift high and hang, crash down with the
## whole body, sink into the impact, haul the weapon back up.
static func overhead(i: float, depth := 0.24) -> Dictionary:
	var a := i * 0.55
	var b := i * 0.86
	var c := _c(i + 0.12)
	return {
		R.UARM_R: [[0, ARM_R], [a, Vector3(2.1, 0.25, 0.35)], [b, Vector3(2.95, 0.35, 0.22)], [i, Vector3(0.45, 0.22, 0.05)], [c, Vector3(0.1, 0.18, 0.0)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [b, Vector3(1.3, 0, 0)], [i, Vector3(0.1, 0, 0)], [c, Vector3(0.2, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.HAND_R: [[0, ZERO], [b, Vector3(0.45, 0, 0)], [i, Vector3(-0.5, 0, 0)], [1, ZERO]],
		R.SPINE: [[0, ZERO], [a, Vector3(0.12, 0.08, 0)], [b, Vector3(0.3, 0.12, 0)], [i, Vector3(-0.62, 0, 0)], [c, Vector3(-0.55, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(0.16, 0.15, 0)], [i, Vector3(-0.28, 0, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(0, 0.03, 0.05)], [i, Vector3(0, -depth, -0.12)], [c, Vector3(0, -depth * 0.9, -0.1)], [1, ZERO]],
		"foot_l": [[0, ZERO], [b, Vector3(0, 0.04, 0.02)], [i, Vector3(-0.03, 0, -0.32)], [1, Vector3(-0.03, 0, -0.1)]],
		"foot_r": [[0, ZERO], [i, Vector3(0.04, 0, 0.12)], [1, ZERO]],
		"fing": [[0, 1.4], [1, 1.4]],
		"two_hand": true,
		"swing": [b, _c(i + 0.08)],
	}


## A flat two-handed sweep: coil far round to the right, step in and carve
## right to left through the whole cone, the momentum twisting the hips after it.
static func sweep(i: float, low := 0.0) -> Dictionary:
	var b := i * 0.78
	var c := _c(i + 0.14)
	return {
		R.UARM_R: [[0, ARM_R], [b, Vector3(1.25 - low, -1.25, 0.75)], [i, Vector3(1.35 - low, 0.15, 0.1)], [c, Vector3(1.2 - low, 1.35, -0.1)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [b, Vector3(1.0, 0, 0)], [i, Vector3(0.12, 0, 0)], [c, Vector3(0.35, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.HAND_R: [[0, ZERO], [b, Vector3(0.2, 0, 0.3)], [i, Vector3(-0.2, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(-0.05, -0.85, 0.05)], [i, Vector3(-0.1, 0.1, 0)], [c, Vector3(-0.08, 0.8, -0.05)], [1, ZERO]],
		R.SPINE: [[0, ZERO], [b, Vector3(0.05, -0.35, 0)], [i, Vector3(-0.2, 0.05, 0)], [c, Vector3(-0.1, 0.4, 0)], [1, ZERO]],
		"rot": [[0, ZERO], [b, Vector3(0, -0.28, 0)], [c, Vector3(0, 0.32, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(0, -0.04, 0.04)], [i, Vector3(0, -0.12 - low * 0.1, -0.08)], [1, ZERO]],
		"foot_r": [[0, ZERO], [b, Vector3(0.06, 0, 0.18)], [1, Vector3(0.03, 0, 0.06)]],
		"foot_l": [[0, ZERO], [i, Vector3(-0.06, 0, -0.24)], [1, Vector3(-0.02, 0, -0.06)]],
		"fing": [[0, 1.4], [1, 1.4]],
		"two_hand": true,
		"swing": [b, c],
	}


## The return stroke: a backhand from the left side across to the right.
static func backhand(i: float) -> Dictionary:
	var m := sweep(i)
	m[R.UARM_R] = [[0, ARM_R], [i * 0.75, Vector3(1.3, 1.25, -0.1)], [i, Vector3(1.35, 0.0, 0.2)], [_c(i + 0.14), Vector3(1.2, -1.2, 0.7)], [1, ARM_R]]
	m[R.CHEST] = [[0, ZERO], [i * 0.75, Vector3(-0.05, 0.8, 0)], [i, Vector3(-0.1, -0.1, 0)], [_c(i + 0.14), Vector3(-0.05, -0.8, 0)], [1, ZERO]]
	m[R.SPINE] = [[0, ZERO], [i * 0.75, Vector3(0, 0.35, 0)], [_c(i + 0.14), Vector3(-0.15, -0.35, 0)], [1, ZERO]]
	m["rot"] = [[0, ZERO], [i * 0.75, Vector3(0, 0.3, 0)], [_c(i + 0.14), Vector3(0, -0.3, 0)], [1, ZERO]]
	m["foot_l"] = [[0, ZERO], [i * 0.75, Vector3(-0.05, 0, 0.12)], [1, ZERO]]
	m["foot_r"] = [[0, ZERO], [i, Vector3(0.07, 0, -0.24)], [1, Vector3(0.02, 0, -0.05)]]
	m["swing"] = [i * 0.75, _c(i + 0.14)]
	return m


## Lunging thrust: draw the weapon back along the hip, then drive it straight
## ahead with a long step and the shoulders behind it.
static func thrust(i: float, reach := 0.55) -> Dictionary:
	var b := i * 0.75
	var c := _c(i + 0.15)
	return {
		R.UARM_R: [[0, ARM_R], [b, Vector3(0.75, -0.45, 0.55)], [i, Vector3(1.5, 0.12, 0.05)], [c, Vector3(1.45, 0.1, 0.05)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [b, Vector3(1.75, 0, 0)], [i, Vector3(0.04, 0, 0)], [c, Vector3(0.1, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.HAND_R: [[0, ZERO], [b, Vector3(-0.6, 0, 0)], [i, Vector3(-1.15, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(0.05, -0.6, 0)], [i, Vector3(-0.2, 0.35, 0)], [c, Vector3(-0.2, 0.3, 0)], [1, ZERO]],
		R.SPINE: [[0, ZERO], [b, Vector3(0.12, -0.2, 0)], [i, Vector3(-0.4, 0.1, 0)], [c, Vector3(-0.38, 0.1, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(0, -0.06, 0.12)], [i, Vector3(0, -0.2, -reach * 0.6)], [c, Vector3(0, -0.2, -reach * 0.6)], [1, ZERO]],
		"foot_l": [[0, ZERO], [b, Vector3(0, 0, 0.05)], [i, Vector3(-0.04, 0, -reach)], [c, Vector3(-0.04, 0, -reach)], [1, ZERO]],
		"foot_r": [[0, ZERO], [i, Vector3(0.05, 0, 0.22)], [1, ZERO]],
		"fing": [[0, 1.4], [1, 1.4]],
		"two_hand": true,
		"swing": [b, c],
	}


## Whirlwind: weapon flung out to the side, the body spins `turns` times on
## the spot between `i0` (the first cut) and `i1` (the last), crouched low.
static func spin(i0: float, i1: float, turns := 2.0) -> Dictionary:
	var b := i0 * 0.7
	return {
		R.UARM_R: [[0, ARM_R], [b, Vector3(1.0, -0.9, 0.9)], [i0, Vector3(1.35, -0.4, 1.0)], [i1, Vector3(1.35, -0.4, 1.0)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [i0, Vector3(0.1, 0, 0)], [i1, Vector3(0.1, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.UARM_L: [[0, ARM_L], [i0, Vector3(1.1, 0.4, -1.1)], [i1, Vector3(1.1, 0.4, -1.1)], [1, ARM_L]],
		R.CHEST: [[0, ZERO], [b, Vector3(0, -0.7, 0)], [i0, Vector3(-0.1, 0.2, 0)], [i1, Vector3(-0.1, 0.2, 0)], [1, ZERO]],
		R.SPINE: [[0, ZERO], [b, Vector3(0.0, -0.3, 0)], [i0, Vector3(-0.25, 0, 0)], [i1, Vector3(-0.25, 0, 0)], [1, ZERO]],
		"turn": [[0, 0.0], [b, -0.06], [i1, turns], [1, turns]],
		"hips": [[0, ZERO], [b, Vector3(0, -0.12, 0)], [i0, Vector3(0, -0.2, 0)], [i1, Vector3(0, -0.2, 0)], [1, ZERO]],
		"fing": [[0, 1.4], [1, 1.4]],
		"swing": [i0 * 0.8, i1],
	}


## Leap and crash: crouch, spring (the body rises `height` body units), the
## weapon goes up over the head in the air and comes down with the landing at `land`.
static func leap(up: float, land: float, height := 0.75) -> Dictionary:
	var crouch := up * 0.75
	var peak := (up + land) * 0.5
	var c := _c(land + 0.15)
	return {
		R.UARM_R: [[0, ARM_R], [crouch, Vector3(-0.4, 0, 0.3)], [up, Vector3(1.6, 0.2, 0.3)], [peak, Vector3(2.9, 0.3, 0.2)], [land, Vector3(0.3, 0.2, 0.05)], [c, Vector3(0.15, 0.2, 0)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [peak, Vector3(1.3, 0, 0)], [land, Vector3(0.1, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.UARM_L: [[0, ARM_L], [crouch, Vector3(-0.4, 0, -0.35)], [up, Vector3(1.2, 0, -0.5)], [1, ARM_L]],
		R.SPINE: [[0, ZERO], [crouch, Vector3(-0.45, 0, 0)], [up, Vector3(0.1, 0, 0)], [peak, Vector3(0.3, 0, 0)], [land, Vector3(-0.6, 0, 0)], [c, Vector3(-0.5, 0, 0)], [1, ZERO]],
		R.HEAD: [[0, ZERO], [crouch, Vector3(-0.3, 0, 0)], [peak, Vector3(-0.2, 0, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [crouch, Vector3(0, -0.3, 0.05)], [up, Vector3(0, 0.15, 0)], [peak, Vector3(0, height, 0)], [land * 0.97, Vector3(0, 0.12, 0)], [land, Vector3(0, -0.32, -0.08)], [c, Vector3(0, -0.28, -0.06)], [1, ZERO]],
		"foot_l": [[0, ZERO], [up, ZERO], [peak, Vector3(0, height * 0.75, 0.08)], [land * 0.97, Vector3(0, 0.06, -0.2)], [land, Vector3(-0.04, 0, -0.3)], [1, ZERO]],
		"foot_r": [[0, ZERO], [up, ZERO], [peak, Vector3(0, height * 0.68, 0.18)], [land * 0.97, Vector3(0, 0.05, 0.1)], [land, Vector3(0.05, 0, 0.14)], [1, ZERO]],
		"fing": [[0, 1.4], [1, 1.4]],
		"two_hand": true,
		"swing": [peak, _c(land + 0.06)],
	}


## A lowered-shoulder charge: the weapon trails low behind, the head drives forward.
## Holds the pose between `go` and `stop` (the entity is moving), then skids.
static func charge(go: float, stop: float) -> Dictionary:
	var c := _c(stop + 0.15)
	return {
		R.UARM_R: [[0, ARM_R], [go * 0.7, Vector3(-0.6, 0, 0.35)], [stop, Vector3(-0.5, 0, 0.35)], [c, Vector3(1.2, 0.3, 0.1)], [1, ARM_R]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [go, Vector3(0.3, 0, 0)], [c, Vector3(0.4, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.UARM_L: [[0, ARM_L], [go * 0.7, Vector3(0.9, -0.3, -0.25)], [stop, Vector3(0.9, -0.3, -0.25)], [1, ARM_L]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [go, Vector3(1.6, 0, 0)], [stop, Vector3(1.6, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.SPINE: [[0, ZERO], [go * 0.7, Vector3(-0.3, 0.3, 0)], [go, Vector3(-0.6, 0.35, 0)], [stop, Vector3(-0.6, 0.35, 0)], [c, Vector3(0.15, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [go, Vector3(-0.25, 0.3, 0)], [stop, Vector3(-0.25, 0.3, 0)], [1, ZERO]],
		R.HEAD: [[0, ZERO], [go, Vector3(-0.55, -0.3, 0)], [stop, Vector3(-0.55, -0.3, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [go * 0.7, Vector3(0, -0.18, 0.08)], [go, Vector3(0, -0.12, 0)], [stop, Vector3(0, -0.12, 0)], [c, Vector3(0, -0.22, 0.08)], [1, ZERO]],
		"foot_l": [[0, ZERO], [stop, ZERO], [c, Vector3(-0.04, 0, -0.35)], [1, ZERO]],
		"fing": [[0, 1.4], [1, 1.4]],
	}


## Stomp: lift the right knee high, hang, and drive the foot down into the floor.
static func stomp(i: float) -> Dictionary:
	var b := i * 0.8
	var c := _c(i + 0.15)
	return {
		R.UARM_L: [[0, ARM_L], [b, Vector3(0.6, 0.2, -1.0)], [i, Vector3(0.3, 0, -0.5)], [1, ARM_L]],
		R.UARM_R: [[0, ARM_R], [b, Vector3(0.8, -0.3, 0.9)], [i, Vector3(0.4, 0, 0.4)], [1, ARM_R]],
		R.SPINE: [[0, ZERO], [b, Vector3(0.2, 0, -0.1)], [i, Vector3(-0.4, 0, 0.05)], [c, Vector3(-0.3, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(0.15, 0, 0)], [i, Vector3(-0.2, 0, 0)], [1, ZERO]],
		"rot": [[0, ZERO], [b, Vector3(0, 0, -0.12)], [i, Vector3(0, 0, 0.04)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(-0.06, 0.05, 0)], [i, Vector3(0, -0.22, -0.04)], [c, Vector3(0, -0.2, 0)], [1, ZERO]],
		"foot_r": [[0, ZERO], [b * 0.6, Vector3(0.04, 0.35, -0.12)], [b, Vector3(0.06, 0.6, -0.18)], [i, Vector3(0.06, 0, -0.14)], [1, Vector3(0.03, 0, -0.05)]],
		"fing": [[0, 1.0], [b, 1.5], [1, 1.2]],
		"jaw": [[0, 0.0], [i, 0.4], [c, 0.3], [1, 0.0]],
	}


## Drive the weapon point-first into the ground with both hands (bone spikes,
## ice lances, pillars): lift it high reversed, then plunge, crouched over it.
static func plant(i: float, wrist := Vector3(0.02, 1.0, -0.42), item := Vector3.DOWN) -> Dictionary:
	var b := i * 0.7
	var c := _c(i + 0.2)
	var up := wrist + Vector3(0, 0.55, 0.1)
	return {
		R.SPINE: [[0, ZERO], [b, Vector3(0.25, 0, 0)], [i, Vector3(-0.35, 0, 0)], [c, Vector3(-0.32, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(0.12, 0, 0)], [i, Vector3(-0.2, 0, 0)], [1, ZERO]],
		R.HEAD: [[0, ZERO], [b, Vector3(-0.15, 0, 0)], [i, Vector3(0.25, 0, 0)], [1, ZERO]],
		"grip_r": [[0, up, item, Vector3(-1, 0, 0.35)], [b, up, item, Vector3(-1, 0, 0.35)], [i, wrist, item, Vector3(-1, 0, 0.35)], [1, wrist, item, Vector3(-1, 0, 0.35)]],
		"grip_l": [[0, up + Vector3(-0.07, 0.08, 0), item, Vector3(1, 0, 0.35)], [b, up + Vector3(-0.07, 0.08, 0), item, Vector3(1, 0, 0.35)], [i, wrist + Vector3(-0.07, 0.08, 0), item, Vector3(1, 0, 0.35)], [1, wrist + Vector3(-0.07, 0.08, 0), item, Vector3(1, 0, 0.35)]],
		"grip_w": [[0, 0.0], [b * 0.6, 1.0], [c, 1.0], [1, 0.0]],
		"hips": [[0, ZERO], [b, Vector3(0, 0.04, 0)], [i, Vector3(0, -0.3, -0.06)], [c, Vector3(0, -0.28, -0.05)], [1, ZERO]],
		"foot_l": [[0, ZERO], [i, Vector3(-0.08, 0, -0.18)], [1, ZERO]],
		"foot_r": [[0, ZERO], [i, Vector3(0.08, 0, 0.12)], [1, ZERO]],
		"fing": [[0, 1.45], [1, 1.45]],
	}


## Rip something heavy from the ground with the off hand and heave it
## overhand (the weapon stays in the right hand).
static func heave(i: float) -> Dictionary:
	var dig := i * 0.35
	var lift := i * 0.75
	var c := _c(i + 0.15)
	return {
		R.UARM_L: [[0, ARM_L], [dig, Vector3(0.6, 0.1, -0.35)], [lift, Vector3(2.8, -0.2, -0.45)], [i, Vector3(1.1, 0.25, -0.1)], [c, Vector3(0.4, 0.4, 0.0)], [1, ARM_L]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [dig, Vector3(0.2, 0, 0)], [lift, Vector3(1.2, 0, 0)], [i, Vector3(0.1, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.UARM_R: [[0, ARM_R], [lift, Vector3(0.6, 0, 0.6)], [i, Vector3(-0.2, 0, 0.4)], [1, ARM_R]],
		R.SPINE: [[0, ZERO], [dig, Vector3(-0.7, 0.2, 0)], [lift, Vector3(0.35, -0.3, 0)], [i, Vector3(-0.45, 0.35, 0)], [c, Vector3(-0.35, 0.3, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [dig, Vector3(-0.3, 0.1, 0)], [lift, Vector3(0.2, -0.45, 0)], [i, Vector3(-0.15, 0.5, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [dig, Vector3(0, -0.3, 0)], [lift, Vector3(0, -0.05, 0.08)], [i, Vector3(0, -0.15, -0.15)], [1, ZERO]],
		"foot_l": [[0, ZERO], [dig, Vector3(-0.06, 0, -0.15)], [lift, Vector3(-0.04, 0, 0.05)], [i, Vector3(-0.04, 0, -0.3)], [1, ZERO]],
		"fing": [[0, 1.0], [dig * 1.3, 1.5], [i, 0.2], [1, 0.8]],
	}


## Spellcasting with the off hand: draw the hand back to the ear, then fling
## it forward `shots` times (one per bolt between i0 and i1).
static func fling(i0: float, i1: float, shots := 3) -> Dictionary:
	var arm := [[0.0, ARM_L], [i0 * 0.7, Vector3(1.4, -0.5, -0.9)]]
	var farm := [[0.0, Vector3(0.3, 0, 0)], [i0 * 0.7, Vector3(1.8, 0, 0)]]
	var fing := [[0.0, 0.5], [i0 * 0.7, 1.4]]
	var chest := [[0.0, ZERO], [i0 * 0.7, Vector3(0.05, -0.45, 0)]]
	for s in shots:
		var at := lerpf(i0, i1, float(s) / maxf(1.0, shots - 1.0))
		var back := at - (i1 - i0) / maxf(2.0, shots * 2.0)
		if s > 0:
			arm.append([back, Vector3(1.35, -0.4, -0.7)])
			farm.append([back, Vector3(1.4, 0, 0)])
			fing.append([back, 1.3])
			chest.append([back, Vector3(0.03, -0.3, 0)])
		arm.append([at, Vector3(1.55, 0.25, -0.15)])
		farm.append([at, Vector3(0.05, 0, 0)])
		fing.append([at, -0.2])
		chest.append([at, Vector3(-0.12, 0.35, 0)])
	arm.append([1.0, ARM_L])
	farm.append([1.0, Vector3(0.3, 0, 0)])
	fing.append([1.0, 0.5])
	chest.append([1.0, ZERO])
	return {
		R.UARM_L: arm,
		R.FARM_L: farm,
		R.CHEST: chest,
		R.SPINE: [[0, ZERO], [i0 * 0.7, Vector3(0.08, -0.15, 0)], [i1, Vector3(-0.12, 0.15, 0)], [1, ZERO]],
		R.HAND_L: [[0, ZERO], [i0, Vector3(-0.7, 0, 0)], [1, ZERO]],
		"foot_l": [[0, ZERO], [i0, Vector3(-0.04, 0, -0.15)], [1, ZERO]],
		"fing": fing,
	}


## Both arms sweep up with the chest thrown back, gathering power, then
## spread wide and down at `i` as it bursts out of the ground (rings, novas, summons).
static func invoke(i: float, rise := 0.0) -> Dictionary:
	var b := i * 0.8
	var c := _c(i + 0.15)
	return {
		R.UARM_L: [[0, ARM_L], [b, Vector3(2.7, 0.2, -0.5)], [i, Vector3(0.8, 0.1, -1.35)], [c, Vector3(0.6, 0.1, -1.25)], [1, ARM_L]],
		R.UARM_R: [[0, ARM_R], [b, Vector3(2.7, -0.2, 0.5)], [i, Vector3(0.8, -0.1, 1.35)], [c, Vector3(0.6, -0.1, 1.25)], [1, ARM_R]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [b, Vector3(0.4, 0, 0)], [i, Vector3(0.1, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [b, Vector3(0.4, 0, 0)], [i, Vector3(0.1, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.SPINE: [[0, ZERO], [b, Vector3(0.3, 0, 0)], [i, Vector3(-0.3, 0, 0)], [c, Vector3(-0.25, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [b, Vector3(0.28, 0, 0)], [i, Vector3(-0.15, 0, 0)], [1, ZERO]],
		R.HEAD: [[0, ZERO], [b, Vector3(0.45, 0, 0)], [i, Vector3(-0.2, 0, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(0, rise, 0)], [i, Vector3(0, -0.2, 0)], [c, Vector3(0, -0.18, 0)], [1, ZERO]],
		"foot_l": [[0, ZERO], [i, Vector3(-0.1, 0, 0)], [1, ZERO]],
		"foot_r": [[0, ZERO], [i, Vector3(0.1, 0, 0)], [1, ZERO]],
		"fing": [[0, 0.6], [b, 1.5], [i, -0.3], [1, 0.6]],
		"jaw": [[0, 0.0], [b, 0.15], [i, 0.45], [1, 0.0]],
	}


## Reach out with the off hand, clench the fist at `i` and yank it back
## (chains, grasping roots, a pull towards the boss).
static func yank(i: float) -> Dictionary:
	var b := i * 0.7
	var c := _c(i + 0.2)
	return {
		R.UARM_L: [[0, ARM_L], [b, Vector3(1.6, 0.1, -0.4)], [i, Vector3(1.6, 0.1, -0.3)], [c, Vector3(0.4, -0.3, -0.6)], [1, ARM_L]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [b, Vector3(0.05, 0, 0)], [i, Vector3(0.1, 0, 0)], [c, Vector3(2.0, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.CHEST: [[0, ZERO], [b, Vector3(-0.1, 0.3, 0)], [c, Vector3(0.2, -0.45, 0)], [1, ZERO]],
		R.SPINE: [[0, ZERO], [b, Vector3(-0.2, 0.1, 0)], [c, Vector3(0.25, -0.2, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [b, Vector3(0, -0.05, -0.08)], [c, Vector3(0, -0.12, 0.12)], [1, ZERO]],
		"foot_l": [[0, ZERO], [b, Vector3(-0.04, 0, -0.2)], [c, Vector3(-0.04, 0, -0.05)], [1, ZERO]],
		"foot_r": [[0, ZERO], [c, Vector3(0.05, 0, 0.12)], [1, ZERO]],
		"fing": [[0, 0.5], [b, -0.3], [i, 1.6], [1, 1.0]],
	}


## Heavy flinch: knocked back half a step, weapon arm thrown wide, head snapped.
static func flinch() -> Dictionary:
	return {
		"add": {
			R.SPINE: [[0, ZERO], [0.25, Vector3(0.35, 0.15, 0.1)], [1, ZERO]],
			R.CHEST: [[0, ZERO], [0.25, Vector3(0.15, 0.2, 0)], [1, ZERO]],
			R.HEAD: [[0, ZERO], [0.2, Vector3(0.4, 0.3, 0.15)], [1, ZERO]],
			R.UARM_R: [[0, ZERO], [0.25, Vector3(-0.4, 0, 0.5)], [1, ZERO]],
			R.UARM_L: [[0, ZERO], [0.25, Vector3(-0.3, 0, -0.6)], [1, ZERO]],
		},
		"hips": [[0, ZERO], [0.25, Vector3(0, -0.08, 0.1)], [1, ZERO]],
		"foot_r": [[0, ZERO], [0.3, Vector3(0.03, 0, 0.16)], [1, ZERO]],
		"jaw": [[0, 0.0], [0.2, 0.3], [1, 0.0]],
	}


## Roar to the sky, fists clenched and arms flung wide, the whole body shaking.
static func bellow(i := 0.35) -> Dictionary:
	return {
		R.UARM_L: [[0, ARM_L], [i * 0.6, Vector3(0.3, 0.2, -0.3)], [i, Vector3(0.6, 0.2, -1.2)], [0.85, Vector3(0.6, 0.2, -1.15)], [1, ARM_L]],
		R.UARM_R: [[0, ARM_R], [i * 0.6, Vector3(0.3, -0.2, 0.3)], [i, Vector3(0.6, -0.2, 1.2)], [0.85, Vector3(0.6, -0.2, 1.15)], [1, ARM_R]],
		R.FARM_L: [[0, Vector3(0.3, 0, 0)], [i, Vector3(1.0, 0, 0)], [1, Vector3(0.3, 0, 0)]],
		R.FARM_R: [[0, Vector3(0.7, 0, 0)], [i, Vector3(1.0, 0, 0)], [1, Vector3(0.7, 0, 0)]],
		R.SPINE: [[0, ZERO], [i * 0.6, Vector3(-0.35, 0, 0)], [i, Vector3(0.25, 0, 0)], [0.85, Vector3(0.22, 0, 0)], [1, ZERO]],
		R.CHEST: [[0, ZERO], [i * 0.6, Vector3(-0.2, 0, 0)], [i, Vector3(0.3, 0, 0)], [0.85, Vector3(0.28, 0, 0)], [1, ZERO]],
		R.HEAD: [[0, ZERO], [i * 0.6, Vector3(-0.3, 0, 0)], [i, Vector3(0.55, 0, 0)], [0.85, Vector3(0.5, 0, 0)], [1, ZERO]],
		"hips": [[0, ZERO], [i * 0.6, Vector3(0, -0.15, 0.05)], [i, Vector3(0, -0.08, 0)], [1, ZERO]],
		"foot_l": [[0, ZERO], [i, Vector3(-0.1, 0, 0)], [1, ZERO]],
		"foot_r": [[0, ZERO], [i, Vector3(0.1, 0, 0)], [1, ZERO]],
		"fing": [[0, 1.0], [i, 1.6], [1, 1.2]],
		"jaw": [[0, 0.0], [i * 0.6, 0.1], [i, 0.55], [0.85, 0.5], [1, 0.0]],
		"shake": [[0, 0.0], [i, 1.0], [0.85, 1.0], [1, 0.0]],
	}


## Sequence: play `parts` ([move, from, to] with the moves authored over 0..1)
## back to back inside one action, e.g. a three-blow combo.
static func chain(parts: Array) -> Dictionary:
	return {"chain": parts}
