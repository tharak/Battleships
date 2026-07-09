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
## by side, {"flagship_lost": bool, "uptime_mult": float, "morale_cap": float}.
## flagship_lost is GDD §5.6's permanent morale penalty and command radius loss
## once a flagship dies (sim/command.gd). uptime_mult/morale_cap are the strategic
## ↔ tactical contract's supply modifiers (issue #14, GDD §5.8's table: ≥66 supply
## → 1.0/100, 33-65 → 0.75/90, <33 → 0.5/75) — set once at battle start from
## strategic state (strategic/battle_bridge.gd), read by Sim._advance_combat
## (uptime_mult multiplies a side's fire_mult) and Morale.regen (morale_cap
## replaces the usual 100.0 ceiling). Default 1.0/100.0 for any battle not seeded
## from the strategic layer (the skirmish menu, every existing test).
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
var fleets: Array[Dictionary] = [
	{"flagship_lost": false, "uptime_mult": 1.0, "morale_cap": 100.0},
	{"flagship_lost": false, "uptime_mult": 1.0, "morale_cap": 100.0},
]
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
