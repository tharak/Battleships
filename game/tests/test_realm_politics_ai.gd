extends SceneTree
## Headless behavior tests for the political AI (issue #26, GDD §11's risk
## register: "Realm AI can't play politics"). Run:
##   godot --headless --path game --script res://tests/test_realm_politics_ai.gd
##
## Same "call the real act(), then step() to observe the effect" pattern
## tests/test_strategic_ai.gd already established for the military AI —
## this file never reimplements the heuristics, it drives the real
## RealmPoliticsAI/StrategicSim/StrategicCommandStream together.
##
## The issue's own literal validation method (many-campaign headless
## batches, survival rates, oscillation/purge-treadmill metrics) lives in a
## scratchpad probe, not a committed test — same "probe and tune, don't
## commit the tuning harness itself" precedent used throughout this project.

var _failures := 0


func _init() -> void:
	print("test_realm_politics_ai — Godot ", Engine.get_version_info()["string"])

	_test_budget_pushes_military_heavy_when_stable()
	_test_budget_pushes_private_heavy_when_individual_seats_are_weaker()
	_test_budget_pushes_public_heavy_when_bloc_seats_are_weaker()
	_test_nudge_never_jumps_the_full_distance_in_one_cycle()
	_test_avg_satisfaction_by_kind_is_a_high_sentinel_for_a_missing_kind()

	_test_patronage_appeases_the_least_satisfied_seated_crony_in_crisis()
	_test_patronage_picks_the_highest_tactics_candidate_when_stable()
	_test_patronage_is_a_no_op_with_no_fleet()

	_test_purge_fires_when_in_trouble_with_margin_and_a_seat_below_the_floor()
	_test_broaden_fires_when_stable_and_healthy_below_the_cap()
	_test_broaden_never_fires_at_exactly_the_cap()
	_test_regime_action_is_blocked_during_an_active_instability_window()

	_test_act_respects_its_own_decision_cadence()

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


## --- budget heuristic ----------------------------------------------------------------------

func _test_budget_pushes_military_heavy_when_stable() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)  # apply_due_commands is a no-op here, just settles tick 0
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	var pol: Dictionary = sim.state.politics[1]
	_check(pol["budget_military"] > 0.4, "stable: military share rises above the default 0.4")
	_check(pol["budget_private"] < 0.3 and pol["budget_public"] < 0.3, "stable: private/public both fall below their default 0.3")


func _test_budget_pushes_private_heavy_when_individual_seats_are_weaker() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	for id in ["fleet_commander", "interior_minister", "treasury_minister"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 0.0
	for id in ["veterans_league", "industrial_bloc", "colonial_assembly"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 70.0
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) != "stable", "test setup: genuinely not stable")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	var pol: Dictionary = sim.state.politics[1]
	_check(pol["budget_private"] > pol["budget_public"], "individual seats weaker: budget favors private over public")
	_check(pol["budget_private"] > 0.3, "individual seats weaker: private share actually rises")


func _test_budget_pushes_public_heavy_when_bloc_seats_are_weaker() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	for id in ["fleet_commander", "interior_minister", "treasury_minister"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 70.0
	for id in ["veterans_league", "industrial_bloc", "colonial_assembly"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 0.0
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) != "stable", "test setup: genuinely not stable")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	var pol: Dictionary = sim.state.politics[1]
	_check(pol["budget_public"] > pol["budget_private"], "bloc seats weaker: budget favors public over private")
	_check(pol["budget_public"] > 0.3, "bloc seats weaker: public share actually rises")


## Design review's own central finding: a full-replacement jump risks
## oscillation. Confirms the fix directly -- an extreme target is only ever
## approached by BUDGET_NUDGE_STEP per cycle, never in one jump.
func _test_nudge_never_jumps_the_full_distance_in_one_cycle() -> void:
	var ai := RealmPoliticsAI.new(1)
	var nudged: float = ai._nudge(0.0, 1.0)
	_check(is_equal_approx(nudged, RealmPoliticsAI.BUDGET_NUDGE_STEP),
		"_nudge: moves by exactly BUDGET_NUDGE_STEP toward a far-away target, not the full distance")


func _test_avg_satisfaction_by_kind_is_a_high_sentinel_for_a_missing_kind() -> void:
	var pol := {"seats": {
		"a": {"name": "A", "kind": "individual", "satisfaction": 10.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 20.0, "weight": 1.0},
	}}  # zero bloc seats -- a real, reachable state (test_regime.gd builds this exact shape)
	_check(is_equal_approx(RealmPoliticsAI._avg_satisfaction_by_kind(pol, "bloc"), 100.0),
		"avg_satisfaction_by_kind: a missing kind returns a high sentinel (never the 'weaker' kind), not a NaN from 0/0")
	_check(is_equal_approx(RealmPoliticsAI._avg_satisfaction_by_kind(pol, "individual"), 15.0),
		"avg_satisfaction_by_kind: a present kind still averages normally")


## --- patronage heuristic -------------------------------------------------------------------

func _test_patronage_appeases_the_least_satisfied_seated_crony_in_crisis() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	_check(sim.state.fleets["F1"]["commander_id"] == "fleet_commander", "test setup: starts on the default commander")
	sim.state.politics[1]["seats"]["interior_minister"]["satisfaction"] = 0.0  # the clear worst
	for id in ["fleet_commander", "treasury_minister", "veterans_league", "industrial_bloc", "colonial_assembly"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 30.0
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) != "stable", "test setup: genuinely not stable")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["commander_id"] == "interior_minister",
		"crisis: command goes to the least-satisfied seated crony, buying their loyalty")


func _test_patronage_picks_the_highest_tactics_candidate_when_stable() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) == "stable", "test setup: default seed is stable")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["commander_id"] == "genius_officer",
		"stable: command goes to the highest-tactics candidate (meritocracy when politically safe), even though unseated")


func _test_patronage_is_a_no_op_with_no_fleet() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)  # side 1 has no fleet at all
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	var has_assign := false
	for cmd in stream.commands:
		if cmd["k"] == "assign_command":
			has_assign = true
	_check(not has_assign, "patronage: no fleet means no assign_command is ever emitted")


## --- regime actions -------------------------------------------------------------------------

func _test_purge_fires_when_in_trouble_with_margin_and_a_seat_below_the_floor() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.politics[1]["seats"]["fleet_commander"]["satisfaction"] = 0.0  # below PURGE_SATISFACTION_FLOOR
	for id in ["interior_minister", "treasury_minister", "veterans_league", "industrial_bloc", "colonial_assembly"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 15.0
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) != "stable", "test setup: genuinely not stable")
	_check(sim.state.politics[1]["seats"].size() > Regime.PURGE_MIN_W + RealmPoliticsAI.PURGE_MIN_W_MARGIN,
		"test setup: comfortably above the AI's own purge margin")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.politics[1]["seats"].size() == 5, "purge fires: W drops by exactly one seat")


func _test_broaden_fires_when_stable_and_healthy_below_the_cap() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	for seat in sim.state.politics[1]["seats"].values():
		seat["satisfaction"] = 70.0  # strictly above BROADEN_HEALTH_THRESHOLD (60.0)
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) == "stable", "test setup: genuinely stable")
	var w_before: int = sim.state.politics[1]["seats"].size()
	_check(w_before < RealmPoliticsAI.AI_BROADEN_MAX_W, "test setup: below the AI's own broaden cap")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.politics[1]["seats"].size() == w_before + 1, "broaden fires: W grows by exactly one seat")


## Design review's own off-by-one check: the guard must be `w < 8`, not
## `w <= 8` -- confirms broaden never fires once the AI's own realm has
## already reached its self-imposed cap, so it can never be walked into the
## paper prototype's confirmed W in {9,10,11} valley by this heuristic.
func _test_broaden_never_fires_at_exactly_the_cap() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	var seats: Dictionary = sim.state.politics[1]["seats"]
	while seats.size() < RealmPoliticsAI.AI_BROADEN_MAX_W:
		seats["extra_seat_%d" % seats.size()] = {"name": "Extra", "kind": "individual", "satisfaction": 70.0, "weight": 1.0}
	for seat in seats.values():
		seat["satisfaction"] = 70.0
	_check(seats.size() == RealmPoliticsAI.AI_BROADEN_MAX_W, "test setup: exactly at the AI's own broaden cap")
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 1)) == "stable", "test setup: genuinely stable")
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.politics[1]["seats"].size() == RealmPoliticsAI.AI_BROADEN_MAX_W,
		"broaden never fires once W has already reached the AI's own cap")


func _test_regime_action_is_blocked_during_an_active_instability_window() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.politics[1]["seats"]["fleet_commander"]["satisfaction"] = 0.0
	for id in ["interior_minister", "treasury_minister", "veterans_league", "industrial_bloc", "colonial_assembly"]:
		sim.state.politics[1]["seats"][id]["satisfaction"] = 15.0
	sim.state.politics[1]["instability_ticks_left"] = 5.0
	var w_before: int = sim.state.politics[1]["seats"].size()
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.politics[1]["seats"].size() == w_before,
		"regime action: blocked entirely while an instability window is already active, even under otherwise-purge-worthy conditions")


## --- cadence --------------------------------------------------------------------------------

func _test_act_respects_its_own_decision_cadence() -> void:
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	sim.step(stream)
	var ai := RealmPoliticsAI.new(1)
	ai.act(sim.state, stream)
	sim.step(stream)
	var count_after_first: int = stream.commands.size()

	ai.act(sim.state, stream)  # premature -- POLITICAL_DECISION_PERIOD_TICKS (20) hasn't elapsed
	_check(stream.commands.size() == count_after_first,
		"act: refuses to decide again before its own (much coarser) cadence elapses")
