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
##   strength was lost — GDD §5.3's "losses are always legible"), morale: float
##   (0-100), routed: bool (sticky — see sim/morale.gd for why waver has no
##   equivalent stored field but rout does)
##
## `fleets` is small per-side state that isn't naturally a squadron field: index 0/1
## by side, {"flagship_lost": bool} — GDD §5.6's permanent morale penalty and command
## radius loss once a flagship dies (sim/command.gd).
##
## `terrain` (issue #9, GDD §5.7): id -> {kind: String, pos: Vector2, radius: float}.
## Seeded once via "spawn_terrain" commands and never mutated afterward — there's no
## per-tick terrain system, just geometry queries against this dict (sim/terrain.gd).
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
var fleets: Array[Dictionary] = [{"flagship_lost": false}, {"flagship_lost": false}]
var terrain: Dictionary = {}    # id (String) -> {kind, pos, radius}


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
			"morale": sq["morale"],
			"routed": sq["routed"],
		})
	var terrain_ids := terrain.keys()
	terrain_ids.sort()
	var terrain_list := []
	for id in terrain_ids:
		var f: Dictionary = terrain[id]
		terrain_list.append({
			"id": id, "kind": f["kind"],
			"pos": Commands.pos_to_array(f["pos"]), "radius": f["radius"],
		})
	return {
		"tick": tick,
		"rng_state": int(rng.state),
		"squadrons": squad_list,
		"fleets": [fleets[0], fleets[1]],
		"terrain": terrain_list,
	}


## SHA-256 hex digest over a canonical JSON encoding. Two states with identical
## history produce identical hashes; this is the whole point of the scaffold.
func state_hash() -> String:
	var canonical := JSON.stringify(to_dict())
	return canonical.sha256_text()
