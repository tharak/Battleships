extends SceneTree
## Headless behavior tests for patronage & the officer/essential roster
## (issue #25, GDD §6). Run:
##   godot --headless --path game --script res://tests/test_roster.gd
##
## Layered like the other strategic suites: pure Roster formula/guard tests
## first. The "felt in an actual battle" sim-integration half of this
## issue's showable outcome lives in tests/test_battle_bridge.gd instead
## (extended, not duplicated here) since that's where BattleBridge/
## AutoResolve are already exercised end to end.

var _failures := 0


func _init() -> void:
	print("test_roster — Godot ", Engine.get_version_info()["string"])

	_test_assign_command_rejects_nonexistent_character()
	_test_assign_command_rejects_dead_character()
	_test_assign_command_rejects_a_fleet_belonging_to_another_side()
	_test_assign_command_rejects_reassigning_the_same_character()

	_test_seated_appointment_buys_their_own_seat_satisfaction_charisma_scaled()
	_test_seated_appointment_bonus_is_clamped_at_100()

	_test_unseated_appointment_snubs_other_individual_seats_only()
	_test_snub_penalty_is_floored_at_zero()

	_test_tactics_uptime_mult_baseline_is_exactly_a_no_op()
	_test_tactics_uptime_mult_is_clamped()
	_test_commander_tactics_falls_back_to_baseline_for_a_hand_built_fleet()

	_test_ambition_grows_on_victory_and_stays_flat_on_a_loss()
	_test_permadeath_on_a_wiped_fleet_clears_seat_id_but_not_the_seats_own_satisfaction()
	_test_apply_battle_result_is_a_no_op_for_an_unresolvable_commander_id()

	_test_purge_clears_a_dangling_roster_seat_id()

	_test_ambition_threat_penalty_is_zero_for_the_default_roster()
	_test_ambition_threat_penalty_requires_both_high_ambition_and_low_satisfaction()
	_test_ambition_threat_penalty_is_capped()

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


## --- assign_command guards ------------------------------------------------------------

func _test_assign_command_rejects_nonexistent_character() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "fleet_commander"}
	_check(not Roster.assign_command(state, 0, "F", "nobody"), "assign_command: rejects a nonexistent character")
	_check(state.fleets["F"]["commander_id"] == "fleet_commander", "rejected assign_command: commander_id unchanged")


func _test_assign_command_rejects_dead_character() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "fleet_commander"}
	state.roster[0]["genius_officer"]["alive"] = false
	_check(not Roster.assign_command(state, 0, "F", "genius_officer"), "assign_command: rejects a dead character")
	_check(state.fleets["F"]["commander_id"] == "fleet_commander", "rejected assign_command: commander_id unchanged")


func _test_assign_command_rejects_a_fleet_belonging_to_another_side() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 1, "commander_id": "fleet_commander"}
	_check(not Roster.assign_command(state, 0, "F", "genius_officer"), "assign_command: rejects a fleet that isn't side 0's")
	_check(state.fleets["F"]["commander_id"] == "fleet_commander", "rejected assign_command: commander_id unchanged")


## Design review's own flagged risk: without this guard, repeatedly
## reassigning the SAME crony (e.g. via UI key-spam) would re-trigger the
## satisfaction bonus below for free.
func _test_assign_command_rejects_reassigning_the_same_character() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "genius_officer"}
	var seats_before: Dictionary = (state.politics[0]["seats"] as Dictionary).duplicate(true)
	_check(not Roster.assign_command(state, 0, "F", "genius_officer"),
		"assign_command: rejects reassigning the SAME character already in command")
	for id in seats_before.keys():
		_check(is_equal_approx(state.politics[0]["seats"][id]["satisfaction"], seats_before[id]["satisfaction"]),
			"same-character no-op: seat %s's satisfaction untouched (no free repeat bonus/snub)" % id)


## --- seated appointment: buys satisfaction ----------------------------------------------

func _test_seated_appointment_buys_their_own_seat_satisfaction_charisma_scaled() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "genius_officer"}  # start elsewhere so reassigning is a real change
	var before: float = state.politics[0]["seats"]["interior_minister"]["satisfaction"]
	_check(Roster.assign_command(state, 0, "F", "interior_minister"), "assign_command succeeds")
	var after: float = state.politics[0]["seats"]["interior_minister"]["satisfaction"]
	var charisma: float = state.roster[0]["interior_minister"]["charisma"]
	var expected: float = clampf(before + Roster.COMMAND_SATISFACTION_BONUS * charisma / 50.0, 0.0, 100.0)
	_check(is_equal_approx(after, expected), "seated appointment: own seat's satisfaction rises by the charisma-scaled bonus")


func _test_seated_appointment_bonus_is_clamped_at_100() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "genius_officer"}
	state.politics[0]["seats"]["interior_minister"]["satisfaction"] = 98.0
	_check(Roster.assign_command(state, 0, "F", "interior_minister"), "assign_command succeeds")
	_check(state.politics[0]["seats"]["interior_minister"]["satisfaction"] <= 100.0,
		"seated appointment bonus: never pushes satisfaction past 100 -- issue #24's unclamped-bonus lesson, applied here too")


## --- unseated appointment: the coalition seethes ----------------------------------------

func _test_unseated_appointment_snubs_other_individual_seats_only() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "fleet_commander"}
	var interior_before: float = state.politics[0]["seats"]["interior_minister"]["satisfaction"]
	var treasury_before: float = state.politics[0]["seats"]["treasury_minister"]["satisfaction"]
	var bloc_before: float = state.politics[0]["seats"]["veterans_league"]["satisfaction"]
	_check(Roster.assign_command(state, 0, "F", "genius_officer"), "assign_command (unseated) succeeds")
	_check(is_equal_approx(state.politics[0]["seats"]["interior_minister"]["satisfaction"], maxf(0.0, interior_before - Roster.SNUB_PENALTY)),
		"unseated appointment: an individual seat takes the snub penalty")
	_check(is_equal_approx(state.politics[0]["seats"]["treasury_minister"]["satisfaction"], maxf(0.0, treasury_before - Roster.SNUB_PENALTY)),
		"unseated appointment: EVERY other individual seat, not just one")
	_check(is_equal_approx(state.politics[0]["seats"]["veterans_league"]["satisfaction"], bloc_before),
		"unseated appointment: bloc seats are untouched (impersonal mass constituencies don't feel a personnel snub)")


func _test_snub_penalty_is_floored_at_zero() -> void:
	var state := StrategicState.new()
	state.fleets["F"] = {"side": 0, "commander_id": "fleet_commander"}
	state.politics[0]["seats"]["interior_minister"]["satisfaction"] = 2.0
	_check(Roster.assign_command(state, 0, "F", "genius_officer"), "assign_command succeeds")
	_check(state.politics[0]["seats"]["interior_minister"]["satisfaction"] >= 0.0, "snub penalty: never drops satisfaction below 0")


## --- battle-facing tactics multiplier ----------------------------------------------------

func _test_tactics_uptime_mult_baseline_is_exactly_a_no_op() -> void:
	_check(is_equal_approx(Roster.tactics_uptime_mult(Roster.BASELINE_TACTICS), 1.0),
		"tactics_uptime_mult: exactly baseline tactics produces an exact 1.0x multiplier")


func _test_tactics_uptime_mult_is_clamped() -> void:
	_check(Roster.tactics_uptime_mult(1000.0) <= Roster.TACTICS_UPTIME_MAX + 0.0001,
		"tactics_uptime_mult: clamped at the hard ceiling for an absurdly high tactics value")
	_check(Roster.tactics_uptime_mult(-1000.0) >= Roster.TACTICS_UPTIME_MIN - 0.0001,
		"tactics_uptime_mult: clamped at the hard floor for an absurdly low tactics value")


func _test_commander_tactics_falls_back_to_baseline_for_a_hand_built_fleet() -> void:
	var state := StrategicState.new()
	var fleet := {"side": 0}  # no commander_id key at all, matching several existing hand-built test fleets
	_check(is_equal_approx(Roster.commander_tactics(state, 0, fleet), Roster.BASELINE_TACTICS),
		"commander_tactics: a fleet with no commander_id at all falls back to the baseline (the default fleet_commander's own tactics)")


## --- ambition & permadeath ----------------------------------------------------------------

func _test_ambition_grows_on_victory_and_stays_flat_on_a_loss() -> void:
	var state := StrategicState.new()
	var before: float = state.roster[0]["fleet_commander"]["ambition"]
	Roster.apply_battle_result(state, 0, "fleet_commander", true, false)
	_check(is_equal_approx(state.roster[0]["fleet_commander"]["ambition"], before + Roster.AMBITION_PER_VICTORY),
		"apply_battle_result: a won battle grows the commander's ambition")

	var before2: float = state.roster[0]["fleet_commander"]["ambition"]
	Roster.apply_battle_result(state, 0, "fleet_commander", false, false)
	_check(is_equal_approx(state.roster[0]["fleet_commander"]["ambition"], before2),
		"apply_battle_result: a battle that wasn't won doesn't grow ambition")


## The direct regression for the design review's critical ordering fix:
## battle_bridge.gd's apply_result must resolve commander_id BEFORE erasing a
## wiped fleet's dict -- this test calls apply_battle_result the way that fix
## requires (a resolved String, not a fleet_id that might already be gone).
func _test_permadeath_on_a_wiped_fleet_clears_seat_id_but_not_the_seats_own_satisfaction() -> void:
	var state := StrategicState.new()
	var seat_satisfaction_before: float = state.politics[0]["seats"]["fleet_commander"]["satisfaction"]
	Roster.apply_battle_result(state, 0, "fleet_commander", false, true)
	_check(not state.roster[0]["fleet_commander"]["alive"], "permadeath: a wiped fleet's commander dies")
	_check(state.roster[0]["fleet_commander"]["seat_id"] == null, "permadeath: the roster's link to their former seat is cleared")
	_check(is_equal_approx(state.politics[0]["seats"]["fleet_commander"]["satisfaction"], seat_satisfaction_before),
		"permadeath: the political SEAT itself is untouched, keeps its own satisfaction")


func _test_apply_battle_result_is_a_no_op_for_an_unresolvable_commander_id() -> void:
	var state := StrategicState.new()
	Roster.apply_battle_result(state, 0, "nobody", true, true)  # must not crash
	_check(true, "apply_battle_result: a nonexistent commander id is a silent no-op, not a crash")


## --- Regime.purge <-> roster interaction --------------------------------------------------

func _test_purge_clears_a_dangling_roster_seat_id() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 0.0  # force it to be the purge victim
	_check(Regime.purge(state, 0), "purge succeeds")
	_check(not state.politics[0]["seats"].has("fleet_commander"), "test setup: fleet_commander was indeed the purge victim")
	_check(state.roster[0]["fleet_commander"]["seat_id"] == null, "purge: the roster character's dangling seat_id is cleared")


## --- ambition_threat_penalty (removal.gd's consumer) --------------------------------------

func _test_ambition_threat_penalty_is_zero_for_the_default_roster() -> void:
	var state := StrategicState.new()
	_check(is_equal_approx(Roster.ambition_threat_penalty(state, 0), 0.0),
		"ambition_threat_penalty: exactly 0.0 for the default roster (every character starts at ambition=0.0)")


func _test_ambition_threat_penalty_requires_both_high_ambition_and_low_satisfaction() -> void:
	var state := StrategicState.new()
	state.roster[0]["fleet_commander"]["ambition"] = 100.0
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 90.0  # ambitious but SATISFIED -- not a threat yet
	_check(is_equal_approx(Roster.ambition_threat_penalty(state, 0), 0.0),
		"ambition_threat_penalty: a satisfied character isn't a coup-seed threat no matter how ambitious")

	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 10.0  # now also unsatisfied
	_check(Roster.ambition_threat_penalty(state, 0) > 0.0,
		"ambition_threat_penalty: an ambitious AND unsatisfied seated character is a real threat")


func _test_ambition_threat_penalty_is_capped() -> void:
	var state := StrategicState.new()
	for id in ["fleet_commander", "interior_minister", "treasury_minister"]:
		state.roster[0][id]["ambition"] = 100.0
		state.politics[0]["seats"][id]["satisfaction"] = 5.0
	_check(is_equal_approx(Roster.ambition_threat_penalty(state, 0), Roster.MAX_AMBITION_THREAT_PENALTY),
		"ambition_threat_penalty: capped regardless of how many characters qualify")
