extends SceneTree
## Headless behavior tests for the selectorate core (issue #22, GDD §4.5). Run:
##   godot --headless --path game --script res://tests/test_politics.gd
##
## Layered like the other strategic suites: pure Politics formula tests pin
## down the dilution/appetite math exactly, then Sim-integration tests play
## out the issue's own showable outcome -- "moving the budget slider visibly
## moves seat satisfaction and planet grievances in opposite directions" --
## over real ticks, including two integration bugs a design review caught
## before this shipped: a wiped-out realm's politics silently freezing, and
## a degenerate set_budget input poisoning the economy with NaN.

var _failures := 0


func _init() -> void:
	print("test_politics — Godot ", Engine.get_version_info()["string"])

	_test_private_goods_dilutes_as_coalition_grows()
	_test_individual_seats_respond_only_to_private_goods()
	_test_bloc_seats_respond_only_to_public_goods()
	_test_public_goods_lowers_owned_planet_unrest()
	_test_public_goods_does_nothing_to_a_foreign_planet()
	_test_zero_owned_systems_does_not_divide_by_zero()

	_test_set_budget_normalizes_an_out_of_range_input()
	_test_set_budget_rejects_a_degenerate_zero_sum_input()
	_test_set_budget_ignores_an_unknown_side()

	_test_wiped_out_realm_keeps_drifting_instead_of_freezing()
	_test_budget_slider_moves_satisfaction_and_grievance_in_opposite_directions()

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


## --- pure Politics formulas --------------------------------------------------------------

## Revenue chosen to match realistic in-game magnitude (a 4-system realm's
## default income, ~8/tick) rather than a round number -- large enough that
## a small coalition (6 seats, W's default) still saturates satisfaction at
## the ceiling, but small enough that a much bigger one (12 seats, GDD's W
## upper bound) genuinely dilutes below it, so the comparison is real rather
## than both sides capping out at 100.
func _test_private_goods_dilutes_as_coalition_grows() -> void:
	var small := StrategicState.new()
	var small_seats := {}
	for i in range(6):
		small_seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 0.0, "weight": 1.0}
	small.politics[0]["seats"] = small_seats
	var big := StrategicState.new()
	var big_seats := {}
	for i in range(12):
		big_seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 0.0, "weight": 1.0}
	big.politics[0]["seats"] = big_seats

	for t in range(50):
		Politics.advance(small, 0, 8.0)
		Politics.advance(big, 0, 8.0)
	var small_sat: float = small.politics[0]["seats"]["s0"]["satisfaction"]
	var big_sat: float = big.politics[0]["seats"]["s0"]["satisfaction"]
	_check(small_sat > big_sat,
		"dilution: the same revenue spread across more seats leaves each seat less satisfied (got %.1f vs %.1f)" % [small_sat, big_sat])


func _test_individual_seats_respond_only_to_private_goods() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {"a": {"name": "A", "kind": "individual", "satisfaction": 50.0, "weight": 1.0}}
	state.politics[0]["budget_military"] = 0.0
	state.politics[0]["budget_private"] = 0.0
	state.politics[0]["budget_public"] = 1.0  # all public, zero private
	for t in range(50):
		Politics.advance(state, 0, 100.0)
	_check(state.politics[0]["seats"]["a"]["satisfaction"] < 50.0,
		"individual seats: with zero private-goods budget, an individual seat's satisfaction drifts DOWN, unmoved by public spending")


func _test_bloc_seats_respond_only_to_public_goods() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {"a": {"name": "A", "kind": "bloc", "satisfaction": 50.0, "weight": 1.0}}
	state.politics[0]["budget_military"] = 0.0
	state.politics[0]["budget_private"] = 1.0  # all private, zero public
	state.politics[0]["budget_public"] = 0.0
	for t in range(50):
		Politics.advance(state, 0, 100.0)
	_check(state.politics[0]["seats"]["a"]["satisfaction"] < 50.0,
		"bloc seats: with zero public-goods budget, a bloc seat's satisfaction drifts DOWN, unmoved by private spending")


func _test_public_goods_lowers_owned_planet_unrest() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_public"] = 1.0
	state.politics[0]["budget_military"] = 0.0
	state.politics[0]["budget_private"] = 0.0
	state.planets["A1"]["unrest"] = 50.0
	Politics.advance(state, 0, 500.0)
	_check(state.planets["A1"]["unrest"] < 50.0, "public goods: measurably lowers an owned planet's unrest")


func _test_public_goods_does_nothing_to_a_foreign_planet() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_public"] = 1.0
	state.planets["B1"]["unrest"] = 50.0  # owned by side 1, not side 0
	Politics.advance(state, 0, 500.0)
	_check(state.planets["B1"]["unrest"] == 50.0, "public goods: a foreign planet is completely untouched")


func _test_zero_owned_systems_does_not_divide_by_zero() -> void:
	var state := StrategicState.new()
	for id in state.system_owner.keys():
		if state.system_owner[id] == 0:
			state.system_owner[id] = -1  # side 0 owns nothing
	for t in range(10):
		Politics.advance(state, 0, 100.0)
	for seat in state.politics[0]["seats"].values():
		_check(not is_nan(seat["satisfaction"]), "zero systems: seat satisfaction never becomes NaN")


## --- set_budget command -------------------------------------------------------------------

func _test_set_budget_normalizes_an_out_of_range_input() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "set_budget", {"side": 0, "military": 2.0, "private": 1.0, "public": 1.0}))
	sim.apply_due_commands(stream)
	var pol: Dictionary = sim.state.politics[0]
	var total: float = pol["budget_military"] + pol["budget_private"] + pol["budget_public"]
	_check(is_equal_approx(total, 1.0), "set_budget: always renormalizes to sum to exactly 1.0")
	_check(is_equal_approx(pol["budget_military"], 0.5), "set_budget: proportions are preserved (2:1:1 -> 0.5:0.25:0.25)")


func _test_set_budget_rejects_a_degenerate_zero_sum_input() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	var before: Dictionary = sim.state.politics[0].duplicate(true)
	stream.record(StrategicCommands.make(0, "set_budget", {"side": 0, "military": 0.0, "private": -5.0, "public": -1.0}))
	sim.apply_due_commands(stream)
	_check(sim.state.politics[0]["budget_military"] == before["budget_military"]
		and sim.state.politics[0]["budget_private"] == before["budget_private"]
		and sim.state.politics[0]["budget_public"] == before["budget_public"],
		"set_budget: a degenerate all-zero/negative input is rejected outright, keeping the prior split")
	_check(not is_nan(sim.state.politics[0]["budget_military"]),
		"set_budget: never produces NaN, which would permanently poison this realm's economy")


func _test_set_budget_ignores_an_unknown_side() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "set_budget", {"side": 99, "military": 1.0, "private": 0.0, "public": 0.0}))
	sim.apply_due_commands(stream)  # should not crash
	_check(true, "set_budget: an unknown side is a safe no-op, not a crash")


## --- Sim integration: the issue's own showable outcome ----------------------------------

## The exact regression for the design review's finding: a realm reduced to
## zero systems must keep drifting its seats toward the (unhappy, zero-
## revenue) target, not freeze at whatever satisfaction it last had.
func _test_wiped_out_realm_keeps_drifting_instead_of_freezing() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	sim.step(stream)
	for seat in sim.state.politics[1]["seats"].values():
		seat["satisfaction"] = 90.0  # artificially happy
	for id in sim.state.system_owner.keys():
		if sim.state.system_owner[id] == 1:
			sim.state.system_owner[id] = -1  # side 1 loses every system
	for t in range(30):
		sim.step(stream)
	var any_drifted := false
	for seat in sim.state.politics[1]["seats"].values():
		if seat["satisfaction"] < 90.0:
			any_drifted = true
	_check(any_drifted, "wiped-out realm: seats keep drifting toward the zero-revenue target, not frozen at their last value")


func _test_budget_slider_moves_satisfaction_and_grievance_in_opposite_directions() -> void:
	var private_leaning := StrategicSim.new()
	var private_stream := StrategicCommandStream.new()
	private_leaning.step(private_stream)
	# Heavy taxation on the player's own systems -- default moderate/moderate
	# policy already settles near 0 unrest on its own (per issue #17's tests),
	# leaving no real grievance for public goods to visibly relieve. Real
	# unrest to work against is what makes "opposite directions" observable.
	for id in ["A1", "A2", "A3", "A4"]:
		private_leaning.state.planets[id]["taxation"] = "heavy"
	private_stream.record(StrategicCommands.make(private_leaning.state.tick, "set_budget",
		{"side": 0, "military": 0.1, "private": 0.8, "public": 0.1}))

	var public_leaning := StrategicSim.new()
	var public_stream := StrategicCommandStream.new()
	public_leaning.step(public_stream)
	for id in ["A1", "A2", "A3", "A4"]:
		public_leaning.state.planets[id]["taxation"] = "heavy"
	public_stream.record(StrategicCommands.make(public_leaning.state.tick, "set_budget",
		{"side": 0, "military": 0.1, "private": 0.1, "public": 0.8}))

	for t in range(300):
		private_leaning.step(private_stream)
		public_leaning.step(public_stream)

	var private_individual_sat: float = private_leaning.state.politics[0]["seats"]["fleet_commander"]["satisfaction"]
	var public_individual_sat: float = public_leaning.state.politics[0]["seats"]["fleet_commander"]["satisfaction"]
	_check(private_individual_sat > public_individual_sat,
		"showable outcome: leaning private makes an individual seat happier than leaning public (got %.1f vs %.1f)" % [
			private_individual_sat, public_individual_sat])

	var private_unrest: float = private_leaning.state.planets["A1"]["unrest"]
	var public_unrest: float = public_leaning.state.planets["A1"]["unrest"]
	_check(public_unrest < private_unrest,
		"showable outcome: leaning public leaves planet unrest LOWER than leaning private -- opposite directions (got %.1f vs %.1f)" % [
			public_unrest, private_unrest])

	var private_bloc_sat: float = private_leaning.state.politics[0]["seats"]["veterans_league"]["satisfaction"]
	var public_bloc_sat: float = public_leaning.state.politics[0]["seats"]["veterans_league"]["satisfaction"]
	_check(public_bloc_sat > private_bloc_sat,
		"showable outcome: leaning public makes a bloc seat happier than leaning private (got %.1f vs %.1f)" % [
			public_bloc_sat, private_bloc_sat])
