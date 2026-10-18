class_name OgygiaGen
extends WorldGen
## Terrain of Ogygia, Calypso's island (dimension 3): one small green island
## in a calm sea that runs to the horizon. A hill rises behind a sandy south
## beach; Calypso's grotto is cut into the hill's south face; a spring pool
## sits in the meadow; cypress and poplar trunks are planted for Flora.
## Self-contained: it reuses WorldGen only for the interfaces VoxelWorld and
## the rest of the game call (generate, column, ground_level, biome_at ...).

const SIZE := 512
const CENTER := Vector2(256, 256)
const SEA := WorldGen.SEA_LEVEL
## Calypso's grotto: chamber centre and the mouth facing the beach.
const GROTTO := Vector3(256.0, SEA + 4.5, 232.0)
const GROTTO_MOUTH := Vector3(256.0, SEA + 2.0, 247.0)
const SPRING := Vector2(276.0, 262.0)
## Where a castaway wakes: on the beach, south of the grotto.
const BEACH := Vector3(256.0, 0.0, 296.0)
const RAFT := Vector3(244.0, 0.0, 309.0)

var _n_shape: FastNoiseLite
var _n_fine: FastNoiseLite
var _spring_level := 0.0


func _init(seed_value: int) -> void:
	super(WorldGen.Dimension.RYFT, seed_value, WorldGen.LATEST_REVISION)
	set("dimension", Ogygia.DIM)
	size = SIZE
	_coarse_n = SIZE / COARSE
	_n_shape = FastNoiseLite.new()
	_n_shape.seed = seed_value ^ 0x0611
	_n_shape.frequency = 0.012
	_n_fine = FastNoiseLite.new()
	_n_fine.seed = seed_value ^ 0x0612
	_n_fine.frequency = 0.06
	_spring_level = height(SPRING.x + 6.5, SPRING.y) - 0.6


func prepare(_progress: Callable = Callable(), _timing := false) -> void:
	pass


func center() -> Vector2:
	return CENTER


func in_bounds(x: int, z: int) -> bool:
	# The sea goes on forever; stream whatever is in view.
	return x > -4096 and z > -4096 and x < SIZE + 4096 and z < SIZE + 4096


func biome_at(x: int, z: int) -> int:
	return Biome.FOREST if height(float(x), float(z)) > SEA + 2.5 else Biome.OCEAN


func climate_at(_pos: Vector3) -> Vector3:
	return Vector3.ZERO


func lake_level(_x: float, _z: float) -> Vector2:
	return Vector2(-INF, 0)


func mountain_weight(_x: float, _z: float) -> float:
	return 0.0


func is_protected(_x: float, _z: float) -> bool:
	return true


func height_map() -> PackedFloat32Array:
	var n := SIZE / COARSE
	var out := PackedFloat32Array()
	out.resize(n * n)
	for iz in n:
		for ix in n:
			out[ix + iz * n] = height(ix * COARSE, iz * COARSE)
	return out


## Smooth ground height (world y of the surface).
func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var warp := _n_shape.get_noise_2d(x, z) * 14.0
	var d := p.distance_to(CENTER) + warp
	# Sea floor shelving into the deep, a beach ring, a meadow and the hill.
	var h := lerpf(SEA - 16.0, SEA - 1.5, smoothstep(150.0, 78.0, d))
	if d < 78.0:
		h = maxf(h, lerpf(SEA - 1.5, SEA + 1.4, smoothstep(78.0, 58.0, d)))
	h += smoothstep(58.0, 40.0, d) * (2.5 + _n_fine.get_noise_2d(x, z) * 0.8)
	var hill := Vector2(GROTTO.x, GROTTO.z - 10.0)
	var hd := p.distance_to(hill) + _n_fine.get_noise_2d(z, x) * 3.0
	h += 15.0 * smoothstep(34.0, 6.0, hd)
	# The spring's basin.
	h -= 2.2 * smoothstep(5.5, 2.0, p.distance_to(SPRING))
	return h


func column(x: int, z: int, _detail: FastNoiseLite, _ridge: FastNoiseLite) -> Vector2:
	return Vector2(floorf(height(x, z) - 1.0 + 0.5), 0.0)


func column_f(x: int, z: int, _detail: FastNoiseLite, _ridge: FastNoiseLite) -> Vector2:
	return Vector2(height(x, z) - 1.0, 0.0)


func surface_height(x: int, z: int) -> int:
	return int(floorf(height(x, z) - 0.5))


func ground_level(x: float, z: float) -> float:
	return height(x, z)


## Signed distance (> 0 inside open air) of the grotto: a domed chamber and
## a passage out to the beach.
func _grotto(p: Vector3) -> float:
	var q := (p - GROTTO) / Vector3(7.0, 4.2, 7.5)
	var room := 1.0 - q.length()
	var a := GROTTO + Vector3(0, -1.5, 3.0)
	var b := GROTTO_MOUTH + Vector3(0, 0.6, 2.0)
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	var c := a.lerp(b, t)
	var r := (p - c) / Vector3(2.6, 2.4, 2.6)
	var tunnel := 1.0 - r.length()
	# A flat, dry floor.
	return minf(maxf(room, tunnel) * 2.5, p.y - (SEA + 1.6))


## A cypress or poplar trunk planted at (x, z), or 0.
func tree_at(x: int, z: int) -> int:
	if x % 7 != 0 or z % 7 != 0:
		return 0
	var hsh := absi(hash(Vector2i(x, z) * 31 + Vector2i(world_seed, 3))) % 100
	var h := height(x, z)
	if h < SEA + 3.0 or Vector2(x, z).distance_to(SPRING) < 7.0:
		return 0
	if Vector2(x, z).distance_to(Vector2(GROTTO_MOUTH.x, GROTTO_MOUTH.z + 4.0)) < 9.0:
		return 0
	if hsh < 32:
		return Blocks.PINE_TRUNK  # dark cypress
	if hsh < 50:
		return Blocks.OAK_TRUNK   # poplar
	return 0


func generate(key: Vector3i) -> Array:
	var blocks := Chunk.empty()
	var dens := Chunk.empty()
	var o := key * Chunk.SIZE
	var any := false
	for z in Chunk.SIZE:
		for x in Chunk.SIZE:
			var wx := o.x + x
			var wz := o.z + z
			var h := height(wx, wz)
			var tree := tree_at(wx, wz)
			var spring := Vector2(wx, wz).distance_to(SPRING) < 6.0
			var cave_near := absf(wx - GROTTO.x) < 14 and wz > GROTTO.z - 12 and wz < GROTTO_MOUTH.z + 6
			for y in Chunk.SIZE:
				var wy := o.y + y
				var c := float(wy) + 0.5
				var s := h - c  # > 0 below the ground surface
				if cave_near and s > -3.0:
					s = minf(s, -_grotto(Vector3(wx + 0.5, c, wz + 0.5)))
				var i := Chunk.index(x, y, z)
				var v := clampi(int(round((0.5 + clampf(s, -1.0, 1.0) * 0.5) * 255.0)), 0, 255)
				if v >= 128:
					var b := Blocks.STONE
					if h < SEA + 2.2:
						b = Blocks.SAND
					elif h - c < 1.2:
						b = Blocks.GRASS
					elif h - c < 3.5:
						b = Blocks.DIRT
					elif h - c < 9.0:
						b = Blocks.LIMESTONE
					blocks[i] = b
					dens[i] = v
					any = true
				else:
					dens[i] = v
					if tree != 0 and c > h - 0.5 and c < h + 5.0:
						blocks[i] = tree
						any = true
					elif (wy <= SEA or (spring and c < _spring_level)) and s < 0.0:
						# The spring and the sea (the grotto stays dry above the sea line).
						blocks[i] = Blocks.WATER
						any = true
	if not any:
		return [PackedByteArray(), PackedByteArray()]
	return [blocks, dens]
