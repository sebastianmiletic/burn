class_name TelegraphShape
extends RefCounted
## Geometry of telegraphed attacks, shared by the visual (TelegraphFx) and the
## server's hit test so what you see is exactly what hits you.
##   circle: size.x = radius
##   cone:   size.x = range, size.y = half-angle in degrees
##   line:   size.x = length, size.y = width (starts at pos, runs along dir)
##   ring:   size.x = inner radius, size.y = outer radius
## Height: anything within `height` metres above/below pos.y counts.
## A shape may carry a visual style after a colon ("circle:geyser",
## "line:wave"); the style only changes the landing effect (TelegraphFx).


## "circle:geyser" -> "circle"
static func base(shape: String) -> String:
	var i := shape.find(":")
	return shape if i < 0 else shape.substr(0, i)


## "circle:geyser" -> "geyser" ("" when unstyled)
static func style(shape: String) -> String:
	var i := shape.find(":")
	return "" if i < 0 else shape.substr(i + 1)


static func contains(shape: String, pos: Vector3, dir: Vector3, size: Vector3, point: Vector3, height := 4.0) -> bool:
	if absf(point.y - pos.y) > height:
		return false
	var d := Vector2(point.x - pos.x, point.z - pos.z)
	var f := Vector2(dir.x, dir.z)
	if f.length_squared() < 1e-6:
		f = Vector2(0, -1)
	f = f.normalized()
	match base(shape):
		"circle":
			return d.length() <= size.x
		"ring":
			var r := d.length()
			return r >= size.x and r <= size.y
		"cone":
			var r := d.length()
			if r > size.x:
				return false
			if r < 0.5:
				return true
			return rad_to_deg(acos(clampf(d.normalized().dot(f), -1.0, 1.0))) <= size.y
		"line":
			var along := d.dot(f)
			var side := absf(d.dot(f.orthogonal()))
			return along >= 0.0 and along <= size.x and side <= size.y * 0.5
	return false


## Shortest way out of the shape (for AI that wants to dodge, and tests).
static func area(shape: String, size: Vector3) -> float:
	match base(shape):
		"circle":
			return PI * size.x * size.x
		"ring":
			return PI * (size.y * size.y - size.x * size.x)
		"cone":
			return size.x * size.x * deg_to_rad(size.y)
		"line":
			return size.x * size.y
	return 0.0
