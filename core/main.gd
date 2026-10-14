extends Node
## Main scene: hands control to the Game state machine.


func _ready() -> void:
	Game.boot()
