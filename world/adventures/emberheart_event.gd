class_name EmberheartEvent
extends RefCounted
## The sword in the stone on Mount Pyrrhos (world revision 5), as pure state so
## the server, the HUD and tests share one rule set:
##
##   DORMANT   the Emberheart sits in the cracked altar; lava spits from the cracks.
##   AWAKENED  someone drew it: the Pyrrhai (fire folk) turn hostile, a countdown
##             starts and the screen shakes harder as it runs down.
##   ERUPTED   the countdown ran out. Whoever is still inside the blast radius
##             (the cone) is caught; whoever escaped keeps the sword.
##
## Not wired into the game yet (no interaction prompt, HUD timer, camera shake
## or eruption effects); see docs/HANDOFF.md section 0000. The altar position
## is Location `mount_pyrrhos` meta `adv["altar"]`; the fire folk are
## `fire_village` meta `adv["fire_folk"]`.

enum State { DORMANT, AWAKENED, ERUPTED }

const COUNTDOWN := 150.0          ## seconds from drawing the sword to the eruption
const SHAKE_MIN := 0.08           ## camera shake the moment the sword is drawn
const SHAKE_MAX := 1.0            ## camera shake in the last seconds
const SPEW_DORMANT := 0.15        ## lava spits per second from the altar's cracks
const SPEW_AWAKENED := 2.5
const ITEM := &"sword_emberheart" ## the overpowered sword the player keeps

var state := State.DORMANT
var remaining := COUNTDOWN
var holder := -1                  ## peer id of whoever drew the sword


## Draw the sword (only once per world). Returns true if it was drawn.
func take(peer: int) -> bool:
	if state != State.DORMANT:
		return false
	state = State.AWAKENED
	holder = peer
	remaining = COUNTDOWN
	return true


## Advance the countdown. Returns true on the frame the volcano erupts.
func tick(delta: float) -> bool:
	if state != State.AWAKENED:
		return false
	remaining = maxf(0.0, remaining - delta)
	if remaining > 0.0:
		return false
	state = State.ERUPTED
	return true


## Fire folk attack on sight once the sword has been drawn.
func fire_folk_hostile() -> bool:
	return state != State.DORMANT


## Camera shake strength 0..1: rises with the countdown (quadratically, so the
## last half minute is violent), none before or after.
func shake() -> float:
	if state != State.AWAKENED:
		return 0.0
	var t := 1.0 - remaining / COUNTDOWN
	return lerpf(SHAKE_MIN, SHAKE_MAX, t * t)


func lava_spew_rate() -> float:
	return SPEW_DORMANT if state == State.DORMANT else (SPEW_AWAKENED if state == State.AWAKENED else 0.0)


## Is a position inside the eruption's blast (the volcano's cone)?
static func in_blast(pos: Vector3) -> bool:
	return Vector2(pos.x, pos.z).distance_to(AdventureTerrain.V) < AdventureTerrain.R * 0.8


## At the eruption: does the holder at `pos` escape and keep the sword?
func holder_escapes(pos: Vector3) -> bool:
	return state == State.ERUPTED and not in_blast(pos)


func to_dict() -> Dictionary:
	return {"state": state, "remaining": remaining, "holder": holder}


func from_dict(d: Dictionary) -> void:
	state = clampi(int(d.get("state", State.DORMANT)), State.DORMANT, State.ERUPTED) as State
	remaining = clampf(float(d.get("remaining", COUNTDOWN)), 0.0, COUNTDOWN)
	holder = int(d.get("holder", -1))
