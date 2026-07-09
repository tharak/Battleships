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
## right rosters with the right supply modifiers. `side0_fleet`/`side1_fleet`
## are fleet ids already confirmed to be side 0 / side 1 respectively (the
## caller sorts detect_contact's pair by side first).
static func seed_skirmish(state: StrategicState, side0_fleet: String, side1_fleet: String) -> void:
	var f0: Dictionary = state.fleets[side0_fleet]
	var f1: Dictionary = state.fleets[side1_fleet]
	SkirmishConfig.player_preset = f0.get("preset", FleetPresets.DEFAULT)
	SkirmishConfig.enemy_preset = f1.get("preset", FleetPresets.DEFAULT)
	SkirmishConfig.terrain_option = "none"
	var mod0 := tactical_modifiers(f0["supply"])
	var mod1 := tactical_modifiers(f1["supply"])
	SkirmishConfig.player_uptime_mult = mod0["uptime_mult"]
	SkirmishConfig.player_morale_cap = mod0["morale_cap"]
	SkirmishConfig.enemy_uptime_mult = mod1["uptime_mult"]
	SkirmishConfig.enemy_morale_cap = mod1["morale_cap"]
	SkirmishConfig.from_map_contact = true
	SkirmishConfig.contact_fleet_ids = [side0_fleet, side1_fleet]


## Battle → strategic write-back (minimal, see this file's docstring): the
## losing fleet is removed from the map, the winning fleet's strength is set to
## its survivors' total. Called once main.tscn's battle concludes and the
## player returns to the map (strategic_map.gd reads BattleResult, see there).
static func apply_result(state: StrategicState, side0_fleet: String, side1_fleet: String,
		side0_strength_left: int, side1_strength_left: int) -> void:
	if side0_strength_left <= 0:
		state.fleets.erase(side0_fleet)
	else:
		state.fleets[side0_fleet]["strength"] = side0_strength_left
	if side1_strength_left <= 0:
		state.fleets.erase(side1_fleet)
	else:
		state.fleets[side1_fleet]["strength"] = side1_strength_left
