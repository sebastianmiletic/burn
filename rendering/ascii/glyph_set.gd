class_name GlyphSet
extends RefCounted
## Glyph ramps used by the ASCII pass.
##
## The compute shader receives one storage buffer: a header of
## (offset, length) pairs, one per ramp, followed by atlas indices.
## Sortable ramps are re-ordered darkest to brightest by the ink coverage the
## glyph atlas measures from the real font, so the ramp stays monotonic at
## every cell size. Fixed ramps keep their order because the shader indexes
## them by meaning (e.g. EDGES[2] is always "/").

enum Ramp { SOLID, GROUND, FOLIAGE, LIQUID, SKY, CLASSIC, EDGES, RAIN, LEAF }

const RAMP_COUNT := 9
const HEADER_INTS := RAMP_COUNT * 2

const RAMPS: Array[String] = [
	" .,:coO0P#%@",  # SOLID: stone, creatures, the dragon
	" .,:;coP0#",  # GROUND: terrain and floors
	" .,'|/\\;:",  # FOLIAGE (fixed): space . , ' | / \ ; :
	" .-~=",  # LIQUID
	" .'`+*",  # SKY: faint cloud texture and stars
	" .'`^\",:;Il!i><~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",  # CLASSIC
	"|-/\\_",  # EDGES (fixed): | - / \ _
	"|/\\'.,",  # RAIN (fixed): | / \ ' . ,
	" .,;*%&@",  # LEAF: canopies read as dense, soft masses
]

const SORTABLE: Array[bool] = [true, true, false, true, true, true, false, false, true]


## Every distinct glyph, in first-seen order. Atlas column i holds glyph i.
static func all_glyphs() -> String:
	var out := ""
	for ramp in RAMPS:
		for i in ramp.length():
			var ch := ramp[i]
			if out.find(ch) == -1:
				out += ch
	return out


## Builds the buffer the shader reads. `coverage` maps glyph -> mean ink (0..1).
static func build_table(coverage: Dictionary) -> PackedInt32Array:
	var glyphs := all_glyphs()
	var table := PackedInt32Array()
	table.resize(HEADER_INTS)
	var offset := 0
	for r in RAMP_COUNT:
		var chars: Array[String] = []
		for i in RAMPS[r].length():
			chars.append(RAMPS[r][i])
		if SORTABLE[r]:
			chars = _sorted_by_coverage(chars, coverage)
		table[r * 2] = offset
		table[r * 2 + 1] = chars.size()
		for ch in chars:
			table.append(glyphs.find(ch))
		offset += chars.size()
	return table


## Ramp contents as a string, decoded from a table. Used by tests and the debug UI.
static func ramp_string(table: PackedInt32Array, ramp: int) -> String:
	var glyphs := all_glyphs()
	var out := ""
	var off := table[ramp * 2]
	for i in table[ramp * 2 + 1]:
		out += glyphs[table[HEADER_INTS + off + i]]
	return out


static func _sorted_by_coverage(chars: Array[String], coverage: Dictionary) -> Array[String]:
	# The space always stays first so empty cells stay empty.
	var rest: Array[String] = chars.slice(1)
	rest.sort_custom(func(a: String, b: String) -> bool:
		var ca: float = coverage.get(a, 0.0)
		var cb: float = coverage.get(b, 0.0)
		if is_equal_approx(ca, cb):
			return chars.find(a) < chars.find(b)
		return ca < cb)
	var out: Array[String] = [chars[0]]
	out.append_array(rest)
	return out
