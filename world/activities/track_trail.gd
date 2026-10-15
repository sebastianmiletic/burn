class_name TrackTrail
extends Entity
## Fresh tracks leading to a hunted beast's den: paired prints pressed into the
## ground every stride, dusted with glowing ash so they read at night and in
## first person through grass. Spawned by the server with the trail's points.

var points := PackedVector3Array()
var style := "paw"
var _mm: MultiMeshInstance3D


func _init() -> void:
	kind = "act_tracks"
	team = Team.NEUTRAL
	body.collides = false
	body.gravity = 0.0


func on_spawned(data: Dictionary) -> void:
	var pts: Variant = data.get("points", PackedVector3Array())
	points = pts if pts is PackedVector3Array else PackedVector3Array(pts)
	style = String(data.get("style", "paw"))
	_build()


func _build() -> void:
	if points.size() < 2:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ActivityModels.paw_mesh()
	var xforms: Array[Transform3D] = []
	var scale := 2.3 if style == "bear" else 1.6
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var yaw := atan2(-dir.x, -dir.z)
		for k in 2:
			var t := 0.25 + 0.5 * k
			var p := a.lerp(b, t) + side * (0.16 if k == 0 else -0.16) * scale
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
			xforms.append(Transform3D(basis, p + Vector3(0, 0.05, 0) - global_position))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.material_override = ItemMats.glow(Color(1.0, 0.45, 0.15), 3.2)
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	# A thin haze over the first prints draws the eye to where the trail starts.
	var haze := ModelKit.embers(self, 10, Vector3(0.6, 0.1, 0.6), 1.6, 0.05, 0.5)
	haze.position = Vector3(0, 0.1, 0)
	haze.emitting = true
	# Ash still smouldering in every few prints: visible over grass and at night.
	for i in range(2, points.size(), 4):
		var motes := ModelKit.embers(self, 5, Vector3(0.25, 0.05, 0.25), 1.8, 0.05, 0.7)
		motes.position = points[i] - global_position + Vector3(0, 0.15, 0)
		motes.emitting = true
