extends SceneTree
## Headless behavior tests for planet attributes & policy sliders (issue #17,
## GDD §4.2). Run:
##   godot --headless --path game --script res://tests/test_planet.gd
##
## Layered like the other strategic suites: pure Planet function/formula tests
## pin down the tables and per-tick math exactly, then Sim-integration tests
## play out the issue's own showable outcome -- "a planet panel where policy
## changes visibly move output and unrest" -- over real ticks.

var _failures := 0


func _init() -> void:
	print("test_planet — Godot ", Engine.get_version_info()["string"])

	_test_taxation_levels_trade_revenue_for_unrest()
	_test_conscription_levels_trade_manpower_for_unrest_and_population()
	_test_occupation_stances_ordered_plunder_worst_integrate_best()
	_test_materiel_output_scales_with_population()
	_test_food_output_scales_with_population()
	_test_neutral_system_does_not_evolve()
	_test_occupation_is_inert_on_a_native_owned_planet()
	_test_garrison_suppresses_unrest()
	_test_loyalty_suppresses_unrest()
	_test_garrison_never_exceeds_manpower()
	_test_population_clamped_at_the_ceiling()
	_test_population_clamped_at_the_floor()

	_test_default_policy_unrest_settles_instead_of_saturating()
	_test_harsh_policy_visibly_raises_unrest_over_time()
	_test_easing_policy_afterward_visibly_lowers_unrest_again()
	_test_garrison_lowers_the_long_run_unrest_equilibrium()
	_test_population_stays_bounded_over_a_long_run()
	_test_set_policy_command_applies_through_the_sim()

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


## --- pure Planet tables/formulas -------------------------------------------------------

func _test_taxation_levels_trade_revenue_for_unrest() -> void:
	var mults: Array = []
	var pushes: Array = []
	for level in Planet.TAXATION_LEVELS:
		mults.append(Planet.TAXATION[level]["revenue_mult"])
		pushes.append(Planet.TAXATION[level]["unrest_target"])
	_check(mults[0] < mults[1] and mults[1] < mults[2] and mults[2] < mults[3],
		"taxation: light -> punitive strictly increases revenue_mult")
	_check(pushes[0] < pushes[1] and pushes[1] < pushes[2] and pushes[2] < pushes[3],
		"taxation: light -> punitive strictly increases its unrest-target contribution")


func _test_conscription_levels_trade_manpower_for_unrest_and_population() -> void:
	var mults: Array = []
	var pushes: Array = []
	var drains: Array = []
	for level in Planet.CONSCRIPTION_LEVELS:
		mults.append(Planet.CONSCRIPTION[level]["manpower_mult"])
		pushes.append(Planet.CONSCRIPTION[level]["unrest_target"])
		drains.append(Planet.CONSCRIPTION[level]["population_drain"])
	_check(mults[0] < mults[1] and mults[1] < mults[2] and mults[2] < mults[3],
		"conscription: volunteer -> total strictly increases manpower_mult")
	_check(pushes[0] < pushes[1] and pushes[1] < pushes[2] and pushes[2] < pushes[3],
		"conscription: volunteer -> total strictly increases its unrest-target contribution")
	_check(drains[0] < drains[1] and drains[1] < drains[2] and drains[2] < drains[3],
		"conscription: volunteer -> total strictly increases population drain")


func _test_occupation_stances_ordered_plunder_worst_integrate_best() -> void:
	var plunder: Dictionary = Planet.OCCUPATION["plunder"]
	var administer: Dictionary = Planet.OCCUPATION["administer"]
	var integrate: Dictionary = Planet.OCCUPATION["integrate"]
	_check(plunder["unrest_target"] > administer["unrest_target"] and administer["unrest_target"] > integrate["unrest_target"],
		"occupation: plunder pushes unrest hardest, integrate the least")
	_check(plunder["loyalty_target"] < administer["loyalty_target"] and administer["loyalty_target"] < integrate["loyalty_target"],
		"occupation: plunder wins the least loyalty, integrate the most")
	_check(plunder["revenue_mult"] > integrate["revenue_mult"],
		"occupation: plunder extracts more revenue than integrate, at the cost of the above")


func _test_materiel_output_scales_with_population() -> void:
	var p := Planet.default_state()
	_check(Planet.materiel_output(p) == Planet.INDUSTRY_BASE,
		"materiel_output: a fresh, default-policy planet produces exactly INDUSTRY_BASE")
	p["population"] = Planet.POP_BASELINE / 2.0
	_check(is_equal_approx(Planet.materiel_output(p), Planet.INDUSTRY_BASE / 2.0),
		"materiel_output: half the population halves the output")


func _test_food_output_scales_with_population() -> void:
	var p := Planet.default_state()
	_check(Planet.food_output(p) == Planet.AGRICULTURE_BASE,
		"food_output: a fresh planet produces exactly AGRICULTURE_BASE")
	p["population"] = Planet.POP_BASELINE * 2.0
	_check(is_equal_approx(Planet.food_output(p), Planet.AGRICULTURE_BASE * 2.0),
		"food_output: double the population doubles the output")


## --- Planet.advance() ------------------------------------------------------------------

func _test_neutral_system_does_not_evolve() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = -1
	var before: Dictionary = state.planets["A2"].duplicate()
	for t in range(50):
		Planet.advance(state, "A2")
	_check(state.planets["A2"] == before, "neutral: an unclaimed system's planet stats never change")


func _test_occupation_is_inert_on_a_native_owned_planet() -> void:
	var state := StrategicState.new()
	# A1 is native to side 0 and (by default) still owned by side 0 -- occupation
	# stance should have zero bearing on it regardless of what it's set to.
	var plunder_state := StrategicState.new()
	plunder_state.planets["A1"]["occupation"] = "plunder"
	var integrate_state := StrategicState.new()
	integrate_state.planets["A1"]["occupation"] = "integrate"
	for t in range(20):
		Planet.advance(state, "A1")
		Planet.advance(plunder_state, "A1")
		Planet.advance(integrate_state, "A1")
	_check(is_equal_approx(state.planets["A1"]["unrest"], plunder_state.planets["A1"]["unrest"])
		and is_equal_approx(state.planets["A1"]["unrest"], integrate_state.planets["A1"]["unrest"]),
		"occupation: inert on a native/home-owned planet, whatever stance it's nominally set to")


func _test_garrison_suppresses_unrest() -> void:
	var bare := StrategicState.new()
	bare.planets["A1"]["taxation"] = "punitive"
	var garrisoned := StrategicState.new()
	garrisoned.planets["A1"]["taxation"] = "punitive"
	garrisoned.planets["A1"]["garrison"] = 80.0
	garrisoned.planets["A1"]["manpower"] = 200.0  # enough to actually hold that garrison
	for t in range(100):
		Planet.advance(bare, "A1")
		Planet.advance(garrisoned, "A1")
	_check(garrisoned.planets["A1"]["unrest"] < bare.planets["A1"]["unrest"],
		"garrison: a stationed garrison settles at meaningfully lower unrest than none at all")


func _test_loyalty_suppresses_unrest() -> void:
	var loyal := StrategicState.new()
	loyal.planets["A1"]["taxation"] = "heavy"
	loyal.planets["A1"]["loyalty"] = 100.0
	var disloyal := StrategicState.new()
	disloyal.planets["A1"]["taxation"] = "heavy"
	disloyal.planets["A1"]["loyalty"] = 0.0
	for t in range(30):
		Planet.advance(loyal, "A1")
		Planet.advance(disloyal, "A1")
	_check(loyal.planets["A1"]["unrest"] < disloyal.planets["A1"]["unrest"],
		"loyalty: a more loyal planet settles at lower unrest under the same policy")


func _test_garrison_never_exceeds_manpower() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["garrison"] = 1000.0
	state.planets["A1"]["manpower"] = 10.0
	Planet.advance(state, "A1")
	_check(state.planets["A1"]["garrison"] <= state.planets["A1"]["manpower"],
		"garrison: clamped down to whatever the manpower pool actually holds")


func _test_population_clamped_at_the_ceiling() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["population"] = Planet.POP_CAP - 0.05  # less than one tick's regrowth
	state.planets["A1"]["conscription"] = "volunteer"  # zero population drain
	Planet.advance(state, "A1")
	_check(state.planets["A1"]["population"] == Planet.POP_CAP,
		"population: clamped at POP_CAP, never pushed over it by regrowth")


func _test_population_clamped_at_the_floor() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["population"] = 0.02  # less than one tick's drain under total conscription
	state.planets["A1"]["conscription"] = "total"
	Planet.advance(state, "A1")
	_check(state.planets["A1"]["population"] == 0.0,
		"population: clamped at 0, never pushed negative by conscription drain")


## --- Sim integration: the issue's own showable outcome ----------------------------------

## Confirms the design-review fix actually holds: unrest drifts toward a settled
## equilibrium under steady policy instead of a raw accumulator rail-pinning at
## 0/100 within a campaign-length tick count.
func _test_default_policy_unrest_settles_instead_of_saturating() -> void:
	var state := StrategicState.new()
	for t in range(300):
		Planet.advance(state, "A1")
	_check(state.planets["A1"]["unrest"] < 5.0,
		"default policy: a loyal home planet at moderate/moderate settles near zero unrest, not saturated")


func _test_harsh_policy_visibly_raises_unrest_over_time() -> void:
	var state := StrategicState.new()
	for t in range(200):
		Planet.advance(state, "A1")
	var before: float = state.planets["A1"]["unrest"]
	state.planets["A1"]["taxation"] = "punitive"
	state.planets["A1"]["conscription"] = "total"
	for t in range(200):
		Planet.advance(state, "A1")
	_check(state.planets["A1"]["unrest"] > before + 30.0,
		"harsh policy: switching to punitive taxation + total conscription visibly raises unrest")


func _test_easing_policy_afterward_visibly_lowers_unrest_again() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["taxation"] = "punitive"
	state.planets["A1"]["conscription"] = "total"
	for t in range(200):
		Planet.advance(state, "A1")
	var peak: float = state.planets["A1"]["unrest"]
	state.planets["A1"]["taxation"] = "light"
	state.planets["A1"]["conscription"] = "volunteer"
	for t in range(200):
		Planet.advance(state, "A1")
	_check(state.planets["A1"]["unrest"] < peak - 20.0,
		"easing policy: switching back down visibly lowers unrest again -- it's reversible, not a one-way ratchet")


## Deliberately punitive taxation + only MODERATE (not total) conscription -- total
## conscription's population drain is steep enough that, over 400 ticks, it starves
## out the very manpower pool a garrison needs to stay funded (population feeds
## manpower gain; manpower funds garrison upkeep), which would collapse both runs'
## garrisons to the same eroded value and mask the effect this test is checking.
func _test_garrison_lowers_the_long_run_unrest_equilibrium() -> void:
	var bare := StrategicState.new()
	bare.planets["A1"]["taxation"] = "punitive"
	var garrisoned := StrategicState.new()
	garrisoned.planets["A1"]["taxation"] = "punitive"
	garrisoned.planets["A1"]["garrison"] = 80.0
	garrisoned.planets["A1"]["manpower"] = 500.0  # ample buffer so the garrison stays funded throughout
	for t in range(400):
		Planet.advance(bare, "A1")
		Planet.advance(garrisoned, "A1")
	_check(garrisoned.planets["A1"]["garrison"] == 80.0,
		"garrison test setup: the garrison stayed fully funded for the whole run, not eroded partway through")
	_check(garrisoned.planets["A1"]["unrest"] < bare.planets["A1"]["unrest"] - 10.0,
		"garrison: a real, sustained lever against a harsh tax policy")


func _test_population_stays_bounded_over_a_long_run() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["conscription"] = "total"
	var min_seen: float = state.planets["A1"]["population"]
	var max_seen: float = state.planets["A1"]["population"]
	for t in range(1000):
		Planet.advance(state, "A1")
		var pop: float = state.planets["A1"]["population"]
		min_seen = minf(min_seen, pop)
		max_seen = maxf(max_seen, pop)
	_check(min_seen >= 0.0 and max_seen <= Planet.POP_CAP,
		"population: stays within [0, POP_CAP] over a long (1000-tick) run under total conscription")


## The full command path: strategic_map.gd emits set_policy commands, not direct
## state pokes -- confirm StrategicSim actually applies them, including the
## garrison-clamped-to-manpower rule and a missing-system id being a safe no-op.
func _test_set_policy_command_applies_through_the_sim() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "set_policy", {"system": "A1", "field": "taxation", "value": "heavy"}))
	stream.record(StrategicCommands.make(0, "set_policy", {"system": "A1", "field": "conscription", "value": "heavy"}))
	stream.record(StrategicCommands.make(0, "set_policy", {"system": "A1", "field": "occupation", "value": "plunder"}))
	stream.record(StrategicCommands.make(0, "set_policy", {"system": "A1", "field": "garrison", "value": 10000.0}))
	stream.record(StrategicCommands.make(0, "set_policy", {"system": "nonexistent", "field": "taxation", "value": "heavy"}))
	sim.step(stream)
	_check(sim.state.planets["A1"]["taxation"] == "heavy", "set_policy: taxation applies through the sim")
	_check(sim.state.planets["A1"]["conscription"] == "heavy", "set_policy: conscription applies through the sim")
	_check(sim.state.planets["A1"]["occupation"] == "plunder", "set_policy: occupation applies through the sim")
	_check(sim.state.planets["A1"]["garrison"] <= sim.state.planets["A1"]["manpower"],
		"set_policy: garrison is clamped to the planet's current manpower, not set to the raw requested value")
