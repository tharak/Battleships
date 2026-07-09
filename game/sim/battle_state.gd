extends RefCounted
class_name BattleState
## Plain-data sim state (GDD §11: "simulation core as plain data + systems,
## decoupled from rendering"). No node, no signals, no engine coupling beyond
## RandomNumberGenerator — safe to run headless, hash, save, and diff.
##
## Squadron fields mirror the validated Python/HTML prototypes:
##   id: String, side: int, pos: Vector2i, facing: int (0-5),
##   strength: int, flag: bool, target: Vector2i (or null = holding position)

var tick: int = 0
var rng: RandomNumberGenerator
var squadrons: Dictionary = {}  # id (String) -> Dictionary


func _init(seed_value: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value


## Canonical dict for hashing/serialization: sorted keys, ints only, no Vector2i
## (which isn't stable across Variant->JSON->Variant round trips) — arrays instead.
func to_dict() -> Dictionary:
	var ids := squadrons.keys()
	ids.sort()
	var squad_list := []
	for id in ids:
		var sq: Dictionary = squadrons[id]
		var target_field = null
		if sq.get("target") != null:
			target_field = Commands.pos_to_array(sq["target"])
		squad_list.append({
			"id": id,
			"side": sq["side"],
			"pos": Commands.pos_to_array(sq["pos"]),
			"facing": sq["facing"],
			"strength": sq["strength"],
			"flag": sq["flag"],
			"target": target_field,
		})
	return {
		"tick": tick,
		"rng_state": int(rng.state),
		"squadrons": squad_list,
	}


## SHA-256 hex digest over a canonical JSON encoding. Two states with identical
## history produce identical hashes; this is the whole point of the scaffold.
func state_hash() -> String:
	var canonical := JSON.stringify(to_dict())
	return canonical.sha256_text()
