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
## → uptime/morale, fleet roster → squadron count/strength, and — issue #25 —
## commander tactics → uptime) and a BATTLE → STRATEGIC write-back (surviving
## strength, plus #25's ambition/permadeath consequences for the assigned
## commander). The table's remaining rows — sub-commander quality, regime
## state, captured commanders, prestige beyond ambition — need systems that
## don't exist yet and stay out of scope here, not silently dropped.

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
	# Issue #19, GDD §5.8: "crew experience (volunteer vs conscript)" folded
	# into the same supply-derived uptime/morale contract #14 already built,
	# not a separate mechanic -- no sim.gd changes needed, both fields are
	# already consumed there (uptime_mult multiplies fire_mult in
	# _advance_combat, morale_cap replaces the regen ceiling in Morale.regen).
	var crew0 := _crew_quality(state, f0["side"])
	var crew1 := _crew_quality(state, f1["side"])
	# Issue #25: commander tactics is a THIRD multiplicative factor, same
	# chaining pattern crew quality already established here (mod * crew *
	# commander) -- Roster.commander_tactics falls back to BASELINE_TACTICS
	# (an exact 1.0x no-op) for a fleet with no commander_id / an unassigned
	# default, so this is a no-op for every campaign that's never touched
	# assign_command.
	var commander0 := Roster.tactics_uptime_mult(Roster.commander_tactics(state, f0["side"], f0))
	var commander1 := Roster.tactics_uptime_mult(Roster.commander_tactics(state, f1["side"], f1))
	SkirmishConfig.player_uptime_mult = mod0["uptime_mult"] * crew0["crew_quality_uptime_mult"] * commander0
	SkirmishConfig.player_morale_cap = clampf(mod0["morale_cap"] + crew0["crew_quality_morale_delta"], 0.0, 100.0)
	SkirmishConfig.enemy_uptime_mult = mod1["uptime_mult"] * crew1["crew_quality_uptime_mult"] * commander1
	SkirmishConfig.enemy_morale_cap = clampf(mod1["morale_cap"] + crew1["crew_quality_morale_delta"], 0.0, 100.0)
	SkirmishConfig.from_map_contact = true
	SkirmishConfig.contact_fleet_ids = [player_fleet, enemy_fleet]
	SkirmishConfig.contact_system = f0["system"]  # both fleets share this system, by definition of a contact


## `side`'s home planet's conscription-level crew-quality entry (Planet.
## CONSCRIPTION), or a moderate-equivalent no-op if it has none — currently
## unreachable (every side maps into Shipyard.SHIPYARDS today) but guarded
## the same defensive way as Manpower.apply_casualties for consistency, not
## because it's reachable now.
static func _crew_quality(state: StrategicState, side: int) -> Dictionary:
	var home := Shipyard.home_system(side)
	if not state.planets.has(home):
		return {"crew_quality_uptime_mult": 1.0, "crew_quality_morale_delta": 0.0}
	return Planet.CONSCRIPTION[state.planets[home]["conscription"]]


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
##
## Issue #19: casualties (pre-battle strength minus post-battle strength-left)
## drain the losing crews' OWN side's home planet's manpower and raise its
## unrest (Manpower.apply_casualties) — read BEFORE the erase/strength-update
## below, since for a wiped fleet the pre-battle value doesn't survive that
## (erase()'d entirely, not just overwritten). Applies to both sides (even the
## "winner" can take real losses) and both the interactive and AI-vs-AI paths,
## same as everything else in this function.
##
## Issue #25: each side's `commander_id` is resolved the SAME way, for the
## SAME reason — Roster.apply_battle_result needs to know who was in command
## to grow their ambition or (if wiped) kill them, and a wiped fleet's dict
## is gone by the time that would otherwise run. Resolved to a String up
## front, never a fleet_id, so Roster.apply_battle_result never touches
## state.fleets at all.
##
## Issue #29's Act 1 opener: `first_contact_resolved` is set true
## UNCONDITIONALLY the first time this function is EVER called in a
## campaign, checked BEFORE any winner-branching below -- a design review
## caught that gating it on "did this contact have a clear winner" would
## leave a mutual wipeout OR a mutual survival on the campaign's actual
## first contact un-flagged, incorrectly letting some LATER, unrelated
## battle's winner receive the "mints your first dangerous hero-admiral"
## bonus instead. The bonus itself is only ever granted in the sub-case
## where there IS a clear winner (the same condition already computed for
## system capture below).
static func apply_result(state: StrategicState, fleet_a: String, fleet_b: String,
		a_strength_left: int, b_strength_left: int, system_id: String) -> void:
	var is_first_contact: bool = not state.era_events.get("first_contact_resolved", false)
	state.era_events["first_contact_resolved"] = true

	var a_side: int = state.fleets[fleet_a]["side"]
	var b_side: int = state.fleets[fleet_b]["side"]
	var a_old: int = int(state.fleets[fleet_a]["strength"])
	var b_old: int = int(state.fleets[fleet_b]["strength"])
	var a_commander: String = state.fleets[fleet_a].get("commander_id", Roster.DEFAULT_COMMANDER_ID)
	var b_commander: String = state.fleets[fleet_b].get("commander_id", Roster.DEFAULT_COMMANDER_ID)
	if a_strength_left <= 0:
		state.fleets.erase(fleet_a)
	else:
		state.fleets[fleet_a]["strength"] = a_strength_left
	if b_strength_left <= 0:
		state.fleets.erase(fleet_b)
	else:
		state.fleets[fleet_b]["strength"] = b_strength_left
	var a_won := a_strength_left > 0 and b_strength_left <= 0
	var b_won := b_strength_left > 0 and a_strength_left <= 0
	if a_won:
		state.system_owner[system_id] = a_side
	elif b_won:
		state.system_owner[system_id] = b_side

	Manpower.apply_casualties(state, a_side, maxi(0, a_old - maxi(a_strength_left, 0)))
	Manpower.apply_casualties(state, b_side, maxi(0, b_old - maxi(b_strength_left, 0)))

	var a_bonus: float = EraEvents.FIRST_CONTACT_HERO_AMBITION_BONUS if (is_first_contact and a_won) else 0.0
	var b_bonus: float = EraEvents.FIRST_CONTACT_HERO_AMBITION_BONUS if (is_first_contact and b_won) else 0.0
	if a_bonus > 0.0 or b_bonus > 0.0:
		state.era_events["last_announcement"] = "First Contact: a set-piece battle establishes early reputation!"
	Roster.apply_battle_result(state, a_side, a_commander, a_won, a_strength_left <= 0, a_bonus)
	Roster.apply_battle_result(state, b_side, b_commander, b_won, b_strength_left <= 0, b_bonus)

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
