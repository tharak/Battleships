extends RefCounted
class_name BattleBridge
## Strategic ↔ tactical contract (issue #14, GDD §5.8): map contacts (two
## opposing fleets in the same system) launch a real tactical battle, seeded
## with strategic state. Bridges strategic_map.tscn to main.tscn purely through
## SkirmishConfig's static vars (skirmish_config.gd) — the same handoff #11
## already built for the skirmish menu, just filled in by a map contact instead
## of a player's menu choices. No direct object references cross the scene
## change; that's the whole reason SkirmishConfig is a plain static-var class
## rather than a Node autoload (see its own docstring for why that matters even
## under `--script` test harnesses).
##
## Scope: this wires the STRATEGIC → BATTLE half of §5.8's contract table (supply
## → uptime/morale, fleet roster → squadron count/strength) and a minimal
## BATTLE → STRATEGIC write-back (surviving strength only). The table's other
## rows — commander/sub-commander quality, regime state, captured commanders,
## prestige — need systems that don't exist yet (a commander roster, the
## political layer) and are out of scope here, not silently dropped.

## GDD §5.8's exact table: supply meter -> weapon uptime / morale cap.
static func tactical_modifiers(supply: float) -> Dictionary:
	if supply >= 66.0:
		return {"uptime_mult": 1.0, "morale_cap": 100.0}
	elif supply >= 33.0:
		return {"uptime_mult": 0.75, "morale_cap": 90.0}
	else:
		return {"uptime_mult": 0.5, "morale_cap": 75.0}


## First pair of opposing, alive fleets currently sharing a system, or [] if
## none. Sorted fleet ids so the result is deterministic when multiple contacts
## exist at once (only the first is resolved per tick; the rest wait their turn
## the next tick once this one's fleets are no longer both present).
static func detect_contact(state: StrategicState) -> Array:
	var ids := state.fleets.keys()
	ids.sort()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a: Dictionary = state.fleets[ids[i]]
			var b: Dictionary = state.fleets[ids[j]]
			if a["side"] != b["side"] and a["system"] == b["system"]:
				return [ids[i], ids[j]]
	return []


## Fills SkirmishConfig from the two contacting fleets so main.tscn spawns the
## right rosters with the right supply modifiers. ONLY ever called for a
## contact that involves the player (strategic_map.gd routes AI-vs-AI contacts
## to auto_resolve_contact/AutoResolve instead, never here) — so, unlike
## apply_result below, `player_fleet`/`enemy_fleet` really do always mean
## exactly that, not an arbitrary pair of strategic sides.
static func seed_skirmish(state: StrategicState, player_fleet: String, enemy_fleet: String) -> void:
	var f0: Dictionary = state.fleets[player_fleet]
	var f1: Dictionary = state.fleets[enemy_fleet]
	SkirmishConfig.player_preset = f0.get("preset", FleetPresets.DEFAULT)
	SkirmishConfig.enemy_preset = f1.get("preset", FleetPresets.DEFAULT)
	SkirmishConfig.player_total_strength = int(f0["strength"])
	SkirmishConfig.enemy_total_strength = int(f1["strength"])
	SkirmishConfig.terrain_option = "none"
	var mod0 := tactical_modifiers(f0["supply"])
	var mod1 := tactical_modifiers(f1["supply"])
	SkirmishConfig.player_uptime_mult = mod0["uptime_mult"]
	SkirmishConfig.player_morale_cap = mod0["morale_cap"]
	SkirmishConfig.enemy_uptime_mult = mod1["uptime_mult"]
	SkirmishConfig.enemy_morale_cap = mod1["morale_cap"]
	SkirmishConfig.from_map_contact = true
	SkirmishConfig.contact_fleet_ids = [player_fleet, enemy_fleet]
	SkirmishConfig.contact_system = f0["system"]  # both fleets share this system, by definition of a contact


## Battle → strategic write-back (minimal, see this file's docstring): the
## losing fleet is removed from the map, the winning fleet's strength is set to
## its survivors' total, and — issue #16 — the winner captures the system this
## was fought over (a mutual wipeout leaves ownership untouched: nobody's left
## to claim it). Used for BOTH a player battle concluding in main.tscn (fleet_a/
## fleet_b positionally match seed_skirmish's player_fleet/enemy_fleet) and an
## AI-vs-AI contact resolved directly via AutoResolve — `fleet_a`/`fleet_b` are
## deliberately generic (matching AutoResolve.resolve's own "a"/"b" convention),
## not "side 0/side 1", since this is called for arbitrary side pairs in the
## AI-vs-AI case.
##
## A survivor that doesn't end this battle owning the system it was just fought
## over — a defeated fleet that got some ships out via the tactical border, a
## mutual withdrawal where neither side broke the other, an AutoResolve loser
## that wasn't wiped out — retreats toward its own nearest owned system instead
## of sitting exposed on ground it doesn't hold. A fleet that already IS
## sitting on one of its own systems (e.g. a defender that held its ground)
## finds itself as the "nearest" one and doesn't move. One rule covers both the
## interactive and auto-resolved paths, since it only looks at the strength/
## ownership numbers both already produce, not at how the battle was fought.
static func apply_result(state: StrategicState, fleet_a: String, fleet_b: String,
		a_strength_left: int, b_strength_left: int, system_id: String) -> void:
	var a_side: int = state.fleets[fleet_a]["side"]
	var b_side: int = state.fleets[fleet_b]["side"]
	if a_strength_left <= 0:
		state.fleets.erase(fleet_a)
	else:
		state.fleets[fleet_a]["strength"] = a_strength_left
	if b_strength_left <= 0:
		state.fleets.erase(fleet_b)
	else:
		state.fleets[fleet_b]["strength"] = b_strength_left
	if a_strength_left > 0 and b_strength_left <= 0:
		state.system_owner[system_id] = a_side
	elif b_strength_left > 0 and a_strength_left <= 0:
		state.system_owner[system_id] = b_side

	if a_strength_left > 0:
		_retreat_if_not_held(state, fleet_a, system_id)
	if b_strength_left > 0:
		_retreat_if_not_held(state, fleet_b, system_id)


## Sends `fleet_id` toward the nearest system its own side currently owns, if
## `system_id` (where it just fought) isn't one of them.
static func _retreat_if_not_held(state: StrategicState, fleet_id: String, system_id: String) -> void:
	var f: Dictionary = state.fleets[fleet_id]
	var side: int = f["side"]
	if state.system_owner.get(system_id, -1) == side:
		return
	var owned: Array[String] = []
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			owned.append(id)
	var path := Galaxy.path_to_nearest(system_id, owned)
	if path.is_empty():
		return
	f["path"] = path
	StrategicSim._start_next_hop(f)
