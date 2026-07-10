extends SceneTree
## Headless behavior tests for the 6 hand-balanced fixed campaign starts
## (issue #27, GDD §8's own cut-line #3). Run:
##   godot --headless --path game --script res://tests/test_starts.gd

var _failures := 0


func _init() -> void:
	print("test_starts — Godot ", Engine.get_version_info()["string"])

	_test_confederacy_is_an_exact_no_op_versus_the_pre_existing_defaults()
	_test_every_recipe_starts_below_the_broaden_ceiling()
	_test_junta_purge_is_unavailable_at_the_exact_start_but_broaden_is_not()
	_test_every_recipe_seeds_zero_instability()
	_test_every_recipe_has_at_least_one_unseated_character()
	_test_apply_touches_every_system_a_side_owns_not_just_the_home_hub()
	_test_recipes_do_not_share_a_mutable_dictionary_across_sides()

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


func _test_confederacy_is_an_exact_no_op_versus_the_pre_existing_defaults() -> void:
	var state := StrategicState.new()
	var pol_before: Dictionary = (state.politics[0] as Dictionary).duplicate(true)
	var roster_before: Dictionary = (state.roster[0] as Dictionary).duplicate(true)
	var materiel_before: float = state.materiel[0]
	var planet_before: Dictionary = (state.planets["A1"] as Dictionary).duplicate(true)

	Starts.apply(state, 0, "confederacy")

	_check(state.politics[0]["seats"] == pol_before["seats"], "confederacy: seats unchanged from the pre-#27 default")
	_check(is_equal_approx(state.politics[0]["s_percent"], pol_before["s_percent"]), "confederacy: s_percent unchanged")
	_check(is_equal_approx(state.politics[0]["budget_military"], pol_before["budget_military"]) and
		is_equal_approx(state.politics[0]["budget_private"], pol_before["budget_private"]) and
		is_equal_approx(state.politics[0]["budget_public"], pol_before["budget_public"]), "confederacy: budget split unchanged")
	_check(is_equal_approx(state.politics[0]["election_countdown"], pol_before["election_countdown"]), "confederacy: election_countdown unchanged")
	_check(state.roster[0] == roster_before, "confederacy: roster unchanged")
	_check(is_equal_approx(state.materiel[0], materiel_before), "confederacy: materiel unchanged")
	_check(state.planets["A1"] == planet_before, "confederacy: planet stats unchanged (empty planet_overrides)")


func _test_every_recipe_starts_below_the_broaden_ceiling() -> void:
	for id in Starts.IDS:
		var w: int = Starts.RECIPES[id]["seats"].size()
		_check(w < Regime.BROADEN_MAX_W, "%s: starting W=%d is strictly below Regime.BROADEN_MAX_W (broaden always available)" % [id, w])


func _test_junta_purge_is_unavailable_at_the_exact_start_but_broaden_is_not() -> void:
	var state := StrategicState.new()
	Starts.apply(state, 0, "junta")
	_check(state.politics[0]["seats"].size() == Regime.PURGE_MIN_W, "test setup: junta starts exactly at the purge floor")
	var seats_before: Dictionary = (state.politics[0]["seats"] as Dictionary).duplicate(true)
	_check(not Regime.purge(state, 0), "junta: purge is correctly unavailable at the exact starting moment")
	_check(state.politics[0]["seats"] == seats_before, "junta: the rejected purge left seats untouched")
	_check(Regime.broaden(state, 0), "junta: broaden remains available -- every regime shape is still reachable, not structurally locked")


func _test_every_recipe_seeds_zero_instability() -> void:
	for id in Starts.IDS:
		var state := StrategicState.new()
		Starts.apply(state, 0, id)
		_check(is_equal_approx(state.politics[0].get("instability_ticks_left", 0.0), 0.0),
			"%s: seeds instability_ticks_left at 0.0 -- never begins inside an instability window" % id)
		_check(not state.politics[0].get("removed_flag", false), "%s: removed_flag starts false" % id)


func _test_every_recipe_has_at_least_one_unseated_character() -> void:
	for id in Starts.IDS:
		var has_unseated := false
		for character in Starts.RECIPES[id]["roster"].values():
			if character["seat_id"] == null:
				has_unseated = true
		_check(has_unseated, "%s: includes at least one unseated roster character (the patronage dilemma stays real)" % id)


func _test_apply_touches_every_system_a_side_owns_not_just_the_home_hub() -> void:
	var state := StrategicState.new()
	var owned: Array[String] = []
	for id in state.system_owner.keys():
		if state.system_owner[id] == 0:
			owned.append(id)
	_check(owned.size() > 1, "test setup: side 0 owns more than just its home hub")

	Starts.apply(state, 0, "junta")  # junta's planet_overrides sets unrest to 30.0
	for id in owned:
		_check(is_equal_approx(state.planets[id]["unrest"], 30.0), "junta: system %s's unrest was updated, not just the home hub" % id)


## The exact risk this file's own docstring flags: a `const` Dictionary is a
## single shared object. If apply() ever forgot a `.duplicate(true)`, two
## sides sharing one recipe would share the SAME seats/roster dict --
## mutating one would silently corrupt the other.
func _test_recipes_do_not_share_a_mutable_dictionary_across_sides() -> void:
	var state := StrategicState.new()
	Starts.apply(state, 0, "oligarchy")
	Starts.apply(state, 1, "oligarchy")
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 1.0
	state.roster[0]["fleet_commander"]["ambition"] = 99.0
	_check(not is_equal_approx(state.politics[1]["seats"]["fleet_commander"]["satisfaction"], 1.0),
		"two sides on the same recipe: mutating side 0's seat does NOT affect side 1's (no shared dict)")
	_check(not is_equal_approx(state.roster[1]["fleet_commander"]["ambition"], 99.0),
		"two sides on the same recipe: mutating side 0's roster does NOT affect side 1's (no shared dict)")
