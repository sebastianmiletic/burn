extends OmniLight3D
## Calypso's hearth: a slow, warm flicker.

var _t := 0.0
var _base := -1.0


func _process(delta: float) -> void:
	if _base < 0.0:
		_base = light_energy
	_t += delta
	light_energy = _base * (0.86 + 0.1 * sin(_t * 7.3) + 0.06 * sin(_t * 17.1 + 1.3))
