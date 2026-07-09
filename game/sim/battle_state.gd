extends RefCounted
class_name BattleState
## Plain-data sim state (GDD §11: "simulation core as plain data + systems,
## decoupled from rendering"). No node, no signals, no engine coupling beyond
## RandomNumberGenerator — safe to run headless, hash, save, and diff.
##
## Squadron fields (GDD §5.1-5.2, continuous 2D plane, not the Phase 0 hex grid):
##   id: String, side: int, pos: Vector2, facing: float (deg), desired_facing: float,
##   target: Vector2 or null (move order; null = holding), arrive_facing: float or
##   null (facing to turn to once `target` is reached — see commands.gd's order_move
##   "face" field, used by formation orders), cohesion: float (0-100), strength: int,
##   flag: bool, dmg_accum: float (fractional damage since the last whole point of
##   strength was lost — GDD §5.3's "losses are always legible")
##
## Deliberate scope call: positions/angles are plain floats, not fixed-point. Bit-exact
## cross-machine determinism (needed for lockstep netcode) depends on sin/cos/atan2
## matching across platforms, which GDD §11 explicitly defers ("netcode itself... is
## post-release"); revisit with fixed-point trig if/when that work starts. Same-machine
## repeatability — what solo play, hotseat, and replays need today — holds with floats
## as long as command order and per-tick operation order are fixed, which they are
## (squadrons always processed in sorted-id order). The determinism test suite is the
## regression guard for this.

var tick: int = 0
var rng: RandomNumberGenerator
var squadrons: Dictionary = {}  # id (String) -> Dictionary


func _init(seed_value: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value


## Canonical dict for hashing/serialization: sorted keys, no Vector2 (arrays instead,
## for stable Variant->JSON->Variant round trips).
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
			"desired_facing": sq["desired_facing"],
			"target": target_field,
			"arrive_facing": sq["arrive_facing"],
			"cohesion": sq["cohesion"],
			"strength": sq["strength"],
			"flag": sq["flag"],
			"dmg_accum": sq["dmg_accum"],
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
