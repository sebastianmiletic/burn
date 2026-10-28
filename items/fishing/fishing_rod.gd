extends RefCounted
## "use_script" of every fishing rod (VillageGoods): right-click hands the
## press to the local player's FishingSession (cast, strike, reel in).


static func use(player: Node, id: String) -> void:
	if player == null or not bool(player.get("is_local")):
		return
	FishingSession.for_player(player as Player).on_use(id)
