class_name ArenaBuilders
extends RefCounted
## Dispatches an arena prop to its builder (worker thread).

static func run(b: ArenaBuild) -> void:
	match b.kind:
		"dragons_keep":
			KeepArena.build(b)
		"throne_of_hades":
			HadesArena.throne(b)
		"gates_of_hades":
			HadesArena.gates(b)
		"tartarus":
			TartarusArena.build(b)
		"mountain_hall":
			MountainArena.build(b)
		"crypt":
			CryptArena.build(b)
		"drowned_spire":
			LairArenas.spire(b)
		"broodmother":
			LairArenas.brood(b)
		"hagsfen":
			LairArenas.hagsfen(b)
		"ryft_lair":
			RyftArena.build(b)
		"kraken_lair":
			SeaArenas.kraken(b)
		"charybdis_maw":
			SeaArenas.charybdis(b)
	b.finish()
