extends Node

# Scenario checkpoint save/load.
# Saves are scenario checkpoints only — no continuous autosave.
# Uses Godot Resource serialisation for portability.

const SAVE_DIR: String = "user://saves/"
const CHECKPOINT_EXT: String = ".tres"


func save_checkpoint(checkpoint_name: String) -> Error:
	# TODO(save): implement Resource-based checkpoint serialisation
	return OK


func load_checkpoint(checkpoint_name: String) -> Resource:
	# TODO(save): implement checkpoint deserialisation and GameState hydration
	return null


func list_checkpoints() -> Array[String]:
	# TODO(save): scan SAVE_DIR and return checkpoint names
	return []


func delete_checkpoint(checkpoint_name: String) -> Error:
	# TODO(save): implement checkpoint deletion
	return OK
