extends SceneTree
## Headless behavior tests for casualties -> manpower -> loyalty feedback
## (issue #19, GDD §5.8). Run:
##   godot --headless --path game --script res://tests/test_manpower.gd
##
## Layered like the other strategic suites: pure Shipyard.home_system/Manpower
## function tests pin down the mechanics exactly, then a Sim-integration test
## plays out the issue's own showable outcome -- "a bloody victory that
## damages the home front it recruited from" -- via the real battle_bridge.gd
## write-back path, not a reimplementation of its logic.

var _failures := 0


func _init() -> void:
	print("test_manpower — Godot ", Engine.get_version_info()["string"])

	_test_home_system_round_trips_for_all_three_realms()
	_test_home_system_unmapped_side_returns_empty()

	_test_apply_casualties_drains_manpower_and_raises_unrest()
	_test_apply_casualties_is_a_no_op_for_zero_or_negative()
	_test_apply_casualties_floors_manpower_at_zero()
	_test_apply_casualties_no_ops_once_the_home_system_is_lost()

	_test_bloody_victory_damages_the_home_front()
	_test_a_fully_wiped_fleet_counts_its_whole_strength_as_casualties()
	_test_losing_your_own_home_system_in_the_same_battle_registers_no_casualties()

	_test_seed_skirmish_crew_quality_moves_uptime_and_morale()

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


## --- Shipyard.home_system ----------------------------------------------------------------

func _test_home_system_round_trips_for_all_three_realms() -> void:
	_check(Shipyard.home_system(0) == "A1", "home_system: side 0's home is A1")
	_check(Shipyard.home_system(1) == "B1", "home_system: side 1's home is B1")
	_check(Shipyard.home_system(2) == "C1", "home_system: side 2's home is C1")


func _test_home_system_unmapped_side_returns_empty() -> void:
	_check(Shipyard.home_system(99) == "", "home_system: an unmapped side returns an empty string, not a crash")


## --- Manpower.apply_casualties -----------------------------------------------------------

func _test_apply_casualties_drains_manpower_and_raises_unrest() -> void:
	var state := StrategicState.new()
	var before_manpower: float = state.planets["A1"]["manpower"]
	var before_unrest: float = state.planets["A1"]["unrest"]
	Manpower.apply_casualties(state, 0, 20)
	_check(is_equal_approx(state.planets["A1"]["manpower"], before_manpower - 20 * Manpower.CASUALTY_MANPOWER_RATIO),
		"apply_casualties: manpower drains by the documented ratio")
	_check(is_equal_approx(state.planets["A1"]["unrest"], before_unrest + 20 * Manpower.CASUALTY_UNREST_PER_LOSS),
		"apply_casualties: unrest rises by the documented ratio")


func _test_apply_casualties_is_a_no_op_for_zero_or_negative() -> void:
	var state := StrategicState.new()
	var before: Dictionary = state.planets["A1"].duplicate()
	Manpower.apply_casualties(state, 0, 0)
	Manpower.apply_casualties(state, 0, -5)
	_check(state.planets["A1"] == before, "apply_casualties: zero or negative casualties change nothing")


func _test_apply_casualties_floors_manpower_at_zero() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["manpower"] = 5.0
	Manpower.apply_casualties(state, 0, 1000)
	_check(state.planets["A1"]["manpower"] == 0.0, "apply_casualties: manpower never goes negative, however large the loss")


## The design review's own caught bug, pinned down as a regression: a realm
## that's lost its home system (captured OR in active rebellion) takes no
## further manpower/unrest pokes there at all -- mirrors Shipyard.rebuild's
## existing "lose your capital, lose the mechanic" precedent for this exact
## table, and specifically avoids a manpower poke silently outliving a later
## Rebellion retake (unlike unrest, which the retake path resets outright).
func _test_apply_casualties_no_ops_once_the_home_system_is_lost() -> void:
	var captured := StrategicState.new()
	captured.system_owner["A1"] = 1  # A1 captured by a rival realm
	var before_captured: Dictionary = captured.planets["A1"].duplicate()
	Manpower.apply_casualties(captured, 0, 50)
	_check(captured.planets["A1"] == before_captured,
		"apply_casualties: a captured home system takes no further pokes for its former owner")

	var rebelling := StrategicState.new()
	rebelling.system_owner["A1"] = Rebellion.REBEL_SIDE
	var before_rebelling: Dictionary = rebelling.planets["A1"].duplicate()
	Manpower.apply_casualties(rebelling, 0, 50)
	_check(rebelling.planets["A1"] == before_rebelling,
		"apply_casualties: a home system in active rebellion takes no further pokes either")


## --- Sim integration: the issue's own showable outcome ----------------------------------

## Exercises the REAL battle_bridge.gd write-back, not a reimplementation --
## a side that wins the fight but takes real losses still sees its own home
## planet's manpower/unrest move.
func _test_bloody_victory_damages_the_home_front() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "strength": 90}
	state.fleets["Red"] = {"side": 1, "system": "B1", "strength": 90}
	var before_manpower: float = state.planets["A1"]["manpower"]
	var before_unrest: float = state.planets["A1"]["unrest"]
	BattleBridge.apply_result(state, "Blue", "Red", 60, 0, "B1")  # Blue wins, but took 30 real losses
	_check(state.planets["A1"]["manpower"] < before_manpower,
		"bloody victory: the winning side's own home planet's manpower actually drops")
	_check(state.planets["A1"]["unrest"] > before_unrest,
		"bloody victory: the winning side's own home planet's unrest actually rises")
	_check(is_equal_approx(state.planets["A1"]["manpower"], before_manpower - 30 * Manpower.CASUALTY_MANPOWER_RATIO),
		"bloody victory: the drain matches exactly 30 casualties (90 - 60 strength left)")


## Fought at A2 -- deliberately NOT either side's own home system, so the
## battle-site capture (system_owner[A2] flips to the winner) can't interfere
## with checking either side's actual home planet (B1's ownership, unlike A2's,
## never changes here). Fighting AT your own home system and losing it in the
## same stroke is a real but separate edge case (see the "home system lost"
## no-op test above -- that guard is exactly why casualties correctly do NOT
## land when the contested system IS the loser's own, freshly-captured, home).
func _test_a_fully_wiped_fleet_counts_its_whole_strength_as_casualties() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "A2", "strength": 90}
	state.fleets["Red"] = {"side": 1, "system": "A2", "strength": 90}
	var before_manpower: float = state.planets["B1"]["manpower"]
	BattleBridge.apply_result(state, "Blue", "Red", 60, 0, "A2")  # Red wiped out entirely
	_check(is_equal_approx(state.planets["B1"]["manpower"], before_manpower - 90 * Manpower.CASUALTY_MANPOWER_RATIO),
		"full wipe: a fleet reduced to zero counts its ENTIRE pre-battle strength as casualties, not zero")


## A real edge case found empirically while writing this suite (not
## hypothetical): a side that fights AT its own home system and loses it in
## the same stroke does NOT register casualties there, because by the time
## Manpower.apply_casualties runs, the winner has already captured it this
## same apply_result call (ownership transfer runs first) -- the "home system
## lost" guard is correctly what fires, not a missed case. Applying the loser's
## casualty-grief to a system the WINNER now owns would be backwards anyway
## (that's occupation-stance territory, a different mechanic).
func _test_losing_your_own_home_system_in_the_same_battle_registers_no_casualties() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "strength": 90}
	state.fleets["Red"] = {"side": 1, "system": "B1", "strength": 90}
	var before: Dictionary = state.planets["B1"].duplicate()
	BattleBridge.apply_result(state, "Blue", "Red", 60, 0, "B1")  # Red wiped out AND loses B1 itself
	_check(state.system_owner["B1"] == 0, "test setup: Blue actually captured B1 this same call")
	_check(state.planets["B1"] == before,
		"losing your own home system: no casualty poke lands there -- it's not Red's to grieve on anymore")


## --- Strategic -> battle: crew quality ---------------------------------------------------

func _test_seed_skirmish_crew_quality_moves_uptime_and_morale() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "dest": null, "preset": "line", "supply": 100.0, "strength": 75}
	state.fleets["Red"] = {"side": 1, "system": "B1", "dest": null, "preset": "line", "supply": 100.0, "strength": 75}

	state.planets["A1"]["conscription"] = "volunteer"
	BattleBridge.seed_skirmish(state, "Blue", "Red")
	var volunteer_uptime: float = SkirmishConfig.player_uptime_mult
	var volunteer_morale: float = SkirmishConfig.player_morale_cap

	state.planets["A1"]["conscription"] = "total"
	BattleBridge.seed_skirmish(state, "Blue", "Red")
	var total_uptime: float = SkirmishConfig.player_uptime_mult
	var total_morale: float = SkirmishConfig.player_morale_cap

	_check(volunteer_uptime > total_uptime,
		"crew quality: volunteer crews give a real, higher uptime than total conscription (got %.3f vs %.3f)" % [volunteer_uptime, total_uptime])
	_check(volunteer_morale > total_morale,
		"crew quality: volunteer crews give a real, higher morale cap than total conscription (got %.1f vs %.1f)" % [volunteer_morale, total_morale])

	state.planets["A1"]["conscription"] = "moderate"
	BattleBridge.seed_skirmish(state, "Blue", "Red")
	_check(is_equal_approx(SkirmishConfig.player_uptime_mult, 1.0),
		"crew quality: moderate conscription (the default) is a no-op on top of full supply's own 1.0")
