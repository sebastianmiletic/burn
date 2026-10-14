class_name RuneCode
extends RefCounted
## Party codes: four runes out of sixteen (16^4 = 65 536 codes).
## Runes are plain indices 0..15; ui/rune_glyph.gd draws them.

const RUNE_COUNT := 16
const LENGTH := 4
## Elder Futhark names, in index order (for logs, tooltips and screen readers).
const NAMES: Array[String] = [
	"Fehu", "Uruz", "Thurisaz", "Ansuz", "Raido", "Kaunan", "Gebo", "Wunjo",
	"Hagalaz", "Naudiz", "Isaz", "Jera", "Eihwaz", "Perthro", "Algiz", "Sowilo",
]


static func random(rng: RandomNumberGenerator = null) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in LENGTH:
		out.append(rng.randi_range(0, RUNE_COUNT - 1) if rng != null else randi() % RUNE_COUNT)
	return out


static func is_valid(runes: PackedInt32Array) -> bool:
	if runes.size() != LENGTH:
		return false
	for r in runes:
		if r < 0 or r >= RUNE_COUNT:
			return false
	return true


## 4 runes -> 16-bit integer (first rune is the most significant nibble).
static func encode(runes: PackedInt32Array) -> int:
	if not is_valid(runes):
		return -1
	var v := 0
	for r in runes:
		v = (v << 4) | r
	return v


static func decode(value: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if value < 0 or value >= 1 << (4 * LENGTH):
		return out
	for i in range(LENGTH - 1, -1, -1):
		out.append((value >> (4 * i)) & 0xF)
	return out


## "R3-R12-R0-R7"
static func to_text(runes: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for r in runes:
		parts.append("R%d" % r)
	return "-".join(parts)


## Accepts "R3-R12-R0-R7", "3-12-0-7", "3 12 0 7" or rune names ("Ansuz-Gebo-...").
## Returns an empty array if the text is not a valid code.
static func from_text(text: String) -> PackedInt32Array:
	var cleaned := text.strip_edges().replace(",", " ").replace("-", " ")
	var out := PackedInt32Array()
	for part in cleaned.split(" ", false):
		var p := part.strip_edges()
		var idx := -1
		if p.to_upper().begins_with("R") and p.substr(1).is_valid_int():
			idx = p.substr(1).to_int()
		elif p.is_valid_int():
			idx = p.to_int()
		else:
			for i in NAMES.size():
				if NAMES[i].to_lower() == p.to_lower():
					idx = i
		if idx < 0 or idx >= RUNE_COUNT:
			return PackedInt32Array()
		out.append(idx)
	return out if is_valid(out) else PackedInt32Array()


static func rune_name(index: int) -> String:
	return NAMES[index] if index >= 0 and index < RUNE_COUNT else "?"
