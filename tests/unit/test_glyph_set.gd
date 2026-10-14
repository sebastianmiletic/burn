extends TestCase


func _fake_coverage() -> Dictionary:
	# Coverage = reverse of first-seen order, so sorting must visibly reorder.
	var glyphs := GlyphSet.all_glyphs()
	var cov := {}
	for i in glyphs.length():
		cov[glyphs[i]] = 1.0 - float(i) / glyphs.length()
	cov[" "] = 0.0
	return cov


func test_all_glyphs_unique_and_fit_in_8_bits() -> void:
	var glyphs := GlyphSet.all_glyphs()
	check(glyphs.length() <= 256, "atlas index must fit the 8-bit glyph field")
	for i in glyphs.length():
		check_eq(glyphs.find(glyphs[i]), i, "duplicate glyph %s" % glyphs[i])


func test_header_layout() -> void:
	var table := GlyphSet.build_table(_fake_coverage())
	var offset := 0
	for r in GlyphSet.RAMP_COUNT:
		check_eq(table[r * 2], offset, "offset of ramp %d" % r)
		check_eq(table[r * 2 + 1], GlyphSet.RAMPS[r].length(), "length of ramp %d" % r)
		offset += GlyphSet.RAMPS[r].length()
	check_eq(table.size(), GlyphSet.HEADER_INTS + offset)


func test_fixed_ramps_keep_their_order() -> void:
	var table := GlyphSet.build_table(_fake_coverage())
	for r in GlyphSet.RAMP_COUNT:
		if not GlyphSet.SORTABLE[r]:
			check_eq(GlyphSet.ramp_string(table, r), GlyphSet.RAMPS[r], "ramp %d" % r)
	check_eq(GlyphSet.ramp_string(table, GlyphSet.Ramp.EDGES), "|-/\\_")


func test_sortable_ramps_are_monotonic_and_start_with_space() -> void:
	var cov := _fake_coverage()
	var table := GlyphSet.build_table(cov)
	for r in GlyphSet.RAMP_COUNT:
		if not GlyphSet.SORTABLE[r]:
			continue
		var s := GlyphSet.ramp_string(table, r)
		check_eq(s[0], " ", "ramp %d starts with space" % r)
		check_eq(s.length(), GlyphSet.RAMPS[r].length(), "ramp %d keeps every glyph" % r)
		for i in range(2, s.length()):
			check(cov[s[i - 1]] <= cov[s[i]], "ramp %d not sorted at %d" % [r, i])
