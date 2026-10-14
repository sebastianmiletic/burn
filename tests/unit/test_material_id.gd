extends TestCase
## The material-ID packing must survive Godot's normal_roughness encoding
## for every ID, every roughness, static and dynamic instances.


func test_roundtrip_all_ids_static_and_dynamic() -> void:
	for id in 8:
		for i in 101:
			var r := float(i) / 100.0
			for dynamic in [false, true]:
				var out := AsciiMaterialId.encode_roughness(r, id)
				var byte := AsciiMaterialId.stored_byte(out, dynamic)
				check_eq(AsciiMaterialId.decode_byte(byte), id, "r=%f dynamic=%s" % [r, dynamic])


func test_roughness_error_is_small() -> void:
	for i in 101:
		var r := float(i) / 100.0
		var out := AsciiMaterialId.encode_roughness(r, AsciiMaterialId.FOLIAGE)
		check(absf(out - r) <= 1.0 / 15.0 * 0.5 + 7.0 / 127.0 + 1e-4, "r=%f encoded=%f" % [r, out])
		var byte := AsciiMaterialId.stored_byte(out, false)
		check_near(AsciiMaterialId.decode_roughness(byte), r, 1.0 / 30.0 + 1e-4)


func test_encoded_roughness_stays_in_range() -> void:
	for id in 8:
		check(AsciiMaterialId.encode_roughness(1.0, id) <= 1.0, "id %d at r=1" % id)
		check(AsciiMaterialId.encode_roughness(0.0, id) >= 0.0, "id %d at r=0" % id)


func test_unmarked_material_reads_as_default() -> void:
	# A plain StandardMaterial3D (roughness 1.0) must not be mistaken for a style.
	check_eq(AsciiMaterialId.decode_byte(AsciiMaterialId.stored_byte(1.0, false)), AsciiMaterialId.DEFAULT)


func test_shader_include_matches_gdscript() -> void:
	var src := FileAccess.get_file_as_string("res://rendering/materials/ascii_material.gdshaderinc")
	var ids := {
		"SOLID": AsciiMaterialId.SOLID, "FOLIAGE": AsciiMaterialId.FOLIAGE,
		"LIQUID": AsciiMaterialId.LIQUID, "STREAK": AsciiMaterialId.STREAK,
		"GROUND": AsciiMaterialId.GROUND, "EMISSIVE": AsciiMaterialId.EMISSIVE,
		"CLOTH": AsciiMaterialId.CLOTH, "DEFAULT": AsciiMaterialId.DEFAULT,
	}
	for id_name: String in ids:
		check(src.contains("const int ASCII_%s = %d;" % [id_name, ids[id_name]]), "include constant %s" % id_name)
	check(src.contains("floor(roughness * 15.0 + 0.5)"), "include quantisation")
	check(src.contains("(level * 8.0 + float(ascii_id)) / 127.0"), "include packing")
