class_name CharStyles
extends RefCounted
## Seeded, stable variety for villagers: sex, age, build, height, face, hair,
## beard, skin, and garments by role (farmer, smith, merchant, guard, elder,
## chief). Same seed -> same person.
##
##   HumanoidModel.new(CharStyles.villager("blacksmith", seed))

const SKINS := [Color(0.87, 0.71, 0.58), Color(0.8, 0.62, 0.48), Color(0.7, 0.52, 0.38), Color(0.58, 0.42, 0.3),
	Color(0.46, 0.32, 0.22), Color(0.36, 0.25, 0.18)]
const HAIRS := [Color(0.08, 0.06, 0.05), Color(0.17, 0.11, 0.07), Color(0.3, 0.19, 0.1), Color(0.45, 0.22, 0.1),
	Color(0.62, 0.48, 0.28), Color(0.78, 0.66, 0.42)]
const GREYS := [Color(0.55, 0.53, 0.5), Color(0.72, 0.71, 0.68), Color(0.86, 0.85, 0.82)]
const EARTH := [Color(0.42, 0.32, 0.2), Color(0.33, 0.3, 0.22), Color(0.5, 0.45, 0.33), Color(0.38, 0.27, 0.2),
	Color(0.3, 0.32, 0.27), Color(0.45, 0.38, 0.28), Color(0.55, 0.5, 0.4)]
const DYES := [Color(0.45, 0.2, 0.15), Color(0.25, 0.28, 0.38), Color(0.3, 0.36, 0.24), Color(0.42, 0.3, 0.12),
	Color(0.36, 0.2, 0.32), Color(0.2, 0.33, 0.33), Color(0.55, 0.42, 0.18)]
const RICH := [Color(0.38, 0.14, 0.3), Color(0.14, 0.3, 0.34), Color(0.55, 0.4, 0.1), Color(0.5, 0.12, 0.1), Color(0.18, 0.22, 0.42)]
const LEATHERS := [Color(0.22, 0.14, 0.09), Color(0.3, 0.2, 0.12), Color(0.16, 0.12, 0.1), Color(0.38, 0.26, 0.15)]


static func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi() % list.size()]


static func _vary(rng: RandomNumberGenerator, c: Color, amount := 0.08) -> Color:
	return Color(clampf(c.r * rng.randf_range(1.0 - amount, 1.0 + amount), 0, 1), clampf(c.g * rng.randf_range(1.0 - amount, 1.0 + amount), 0, 1),
		clampf(c.b * rng.randf_range(1.0 - amount, 1.0 + amount), 0, 1))


static func villager(role: String, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var female := rng.randf() < (0.25 if role in ["guard", "blacksmith"] else 0.48)
	var age := pow(rng.randf(), 1.3) * 0.75
	if role in ["elder", "chief"]:
		age = rng.randf_range(0.75, 1.0) if role == "elder" else rng.randf_range(0.45, 0.8)
	var st := {
		"female": female,
		"age": age,
		"skin": _vary(rng, _pick(rng, SKINS), 0.04),
		"height": (rng.randf_range(1.56, 1.74) if female else rng.randf_range(1.66, 1.9)) - 0.05 * maxf(0.0, age - 0.7),
		"bulk": rng.randf_range(0.9, 1.12),
		"jaw": rng.randf_range(0.88, 1.12) * (0.9 if female else 1.0),
		"nose": rng.randf_range(0.85, 1.25),
		"brow": rng.randf_range(0.1, 0.65) * (0.4 if female else 1.0),
		"cheeks": rng.randf_range(0.7, 1.3),
		"leather": _pick(rng, LEATHERS),
		"trousers": _vary(rng, _pick(rng, EARTH)).darkened(rng.randf_range(0.1, 0.4)),
		"cloth": _vary(rng, _pick(rng, EARTH if rng.randf() < 0.6 else DYES)),
		"cloth2": _vary(rng, _pick(rng, DYES)),
		"tunic_length": rng.randf_range(0.25, 0.65),
		"sleeves": _pick(rng, ["long", "long", "elbow", "short"]),
		"footwear": _pick(rng, ["boots", "boots", "shoes", "tall"]),
	}
	if age > 0.35 and rng.randf() < 0.45:
		st["belly"] = rng.randf_range(0.2, 0.7)
	# Hair: greys with age.
	var hair: Color = _pick(rng, HAIRS)
	if age > 0.55:
		hair = hair.lerp(_pick(rng, GREYS), clampf((age - 0.5) * 2.2, 0.0, 1.0))
	st["hair"] = hair
	if female:
		st["hair_style"] = _pick(rng, ["long", "bun", "ponytail", "long", "bun"])
	else:
		var styles := ["short", "short", "long", "topknot"]
		if age > 0.5:
			styles.append_array(["receding", "bald", "short"])
		st["hair_style"] = _pick(rng, styles)
		var r := rng.randf()
		if r < 0.25:
			st["beard"] = "full"
		elif r < 0.37:
			st["beard"] = "goatee"
		elif r < 0.47:
			st["beard"] = "mustache"
		elif r < 0.55 or (age > 0.7 and r < 0.8):
			st["beard"] = "long"
	match role:
		"blacksmith":
			st.merge({"apron": true, "sleeves": _pick(rng, ["short", "none"]), "gloves": true, "muscle": rng.randf_range(0.5, 0.9),
				"bulk": rng.randf_range(1.12, 1.3), "cloth": _vary(rng, Color(0.32, 0.27, 0.22)), "tunic_length": 0.2, "footwear": "boots",
				"held": "pickaxe_iron"}, true)
			if not female and rng.randf() < 0.5:
				st["hair_style"] = _pick(rng, ["bald", "short"])
		"merchant":
			st.merge({"hat": _pick(rng, ["cap", "wide"]), "cloth": _vary(rng, _pick(rng, RICH)), "cloth2": _vary(rng, Color(0.7, 0.55, 0.25)),
				"tunic_length": rng.randf_range(0.75, 0.95), "sash": true, "collar": rng.randf() < 0.6, "vest": rng.randf() < 0.4,
				"belly": maxf(float(st.get("belly", 0.0)), rng.randf_range(0.2, 0.6)), "sleeves": "long", "footwear": "shoes"}, true)
		"guard":
			st.merge({"chainmail": true, "tabard": true, "helmet": _pick(rng, ["nasal", "kettle", "nasal"]), "footwear": "tall",
				"bracers": true, "muscle": rng.randf_range(0.3, 0.6), "metal": _vary(rng, Color(0.5, 0.5, 0.52), 0.05),
				"cloth2": _vary(rng, Color(0.55, 0.15, 0.1)), "tunic_length": 0.5, "held": "sword_iron", "pauldrons": rng.randf() < 0.4}, true)
		"elder":
			st.merge({"robe": true, "cloth": _vary(rng, Color(0.3, 0.22, 0.32)), "cloth2": _vary(rng, Color(0.6, 0.45, 0.2)),
				"hunch": -0.12, "collar": true, "held": "lantern", "footwear": "shoes"}, true)
			if not female:
				st["beard"] = "long"
				st["hair_style"] = _pick(rng, ["long", "receding", "bald"])
		"chief":
			st.merge({"robe": rng.randf() < 0.5, "cloth": _vary(rng, _pick(rng, RICH)), "cloth2": _vary(rng, Color(0.62, 0.5, 0.22)),
				"cape": true, "cloak_color": _vary(rng, _pick(rng, RICH)).darkened(0.2), "collar": true, "footwear": "tall", "vest": rng.randf() < 0.5}, true)
		_:
			# Farmers and townsfolk.
			var r2 := rng.randf()
			if r2 < 0.25:
				st["hat"] = "wide"
				st["cloth2"] = Color(0.72, 0.62, 0.38)  # straw
			elif r2 < 0.4:
				st["hood"] = true
			elif r2 < 0.5:
				st["hat"] = "cap"
			if rng.randf() < 0.3:
				st["vest"] = true
			if rng.randf() < 0.15:
				st["apron"] = true
	return st
