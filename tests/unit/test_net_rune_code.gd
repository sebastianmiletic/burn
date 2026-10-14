extends TestCase


func test_encode_decode_roundtrip_all_codes() -> void:
	for v in range(0, 65536, 97):
		var r := RuneCode.decode(v)
		check(RuneCode.is_valid(r), "decode(%d) valid" % v)
		check_eq(RuneCode.encode(r), v)


func test_first_rune_is_most_significant() -> void:
	check_eq(RuneCode.encode(PackedInt32Array([3, 12, 0, 7])), 3 * 4096 + 12 * 256 + 0 * 16 + 7)


func test_text_forms() -> void:
	var r := PackedInt32Array([3, 12, 0, 7])
	check_eq(RuneCode.to_text(r), "R3-R12-R0-R7")
	check_eq(RuneCode.from_text("R3-R12-R0-R7"), r)
	check_eq(RuneCode.from_text(" 3 12 0 7 "), r)
	check_eq(RuneCode.from_text("ansuz-perthro-fehu-wunjo"), PackedInt32Array([3, 13, 0, 7]))


func test_invalid_codes_rejected() -> void:
	check(RuneCode.from_text("R3-R12-R0").is_empty(), "too short")
	check(RuneCode.from_text("R3-R12-R0-R16").is_empty(), "out of range")
	check(RuneCode.from_text("hello world").is_empty(), "garbage")
	check(not RuneCode.is_valid(PackedInt32Array([1, 2, 3, -1])), "negative")
	check_eq(RuneCode.encode(PackedInt32Array([1, 2])), -1)
	check(RuneCode.decode(65536).is_empty(), "decode out of range")


func test_random_codes_are_valid_and_varied() -> void:
	var seen := {}
	for i in 200:
		var r := RuneCode.random()
		check(RuneCode.is_valid(r), "random valid")
		seen[RuneCode.encode(r)] = true
	check(seen.size() > 150, "random codes vary (%d distinct of 200)" % seen.size())


func test_rune_names() -> void:
	check_eq(RuneCode.rune_name(0), "Fehu")
	check_eq(RuneCode.rune_name(15), "Sowilo")
	check_eq(RuneCode.NAMES.size(), RuneCode.RUNE_COUNT)
