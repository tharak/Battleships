extends SceneTree
## Headless behavior tests for era events & Act 1 campaign flow (issue #29,
## GDD §7). Run:
##   godot --headless --path game --script res://tests/test_era_events.gd
##
## Layered like the other strategic suites: pure trigger/guard tests first,
## then a real StrategicSim.step() integration test for fortress auction --
## the one event whose correctness depends entirely on pipeline ORDERING (a
## design review caught a critical bug here: pushing unrest to
## REBELLION_THRESHOLD at the wrong point in the pipeline would silently
## never fire a real rebellion at all, eroded by Planet.advance's own drift
## before Rebellion.advance ever read it). That fix is only actually proven
## by stepping the real sim, not by asserting the unrest value in isolation.

var _failures := 0


func _init() -> void:
	print("test_era_events — Godot ", Engine.get_version_info()["string"])

	_test_pretender_fires_when_ambitious_seated_character_is_unsatisfied()
	_test_pretender_does_not_fire_below_ambition_threshold()
	_test_pretender_does_not_fire_for_a_satisfied_character()
	_test_pretender_does_not_fire_for_an_unseated_character()
	_test_pretender_fires_only_once()

	_test_debt_crunch_gradual_counter_accumulates_and_fires()
	_test_debt_crunch_counter_unwinds_gradually_not_hard_reset()
	_test_debt_crunch_fires_only_once()

	_test_current_threshold_bump_sums_instability_and_pretender()
	_test_pretender_crisis_blocks_new_regime_actions()

	_test_fortress_auction_does_not_fire_before_min_tick()
	_test_fortress_auction_actually_triggers_a_real_rebellion()
	_test_fortress_auction_fires_only_once()

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


## --- pretender -----------------------------------------------------------------------------

func _test_pretender_fires_when_ambitious_seated_character_is_unsatisfied() -> void:
	var state := StrategicState.new()
	state.roster[0]["fleet_commander"]["ambition"] = 80.0
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 20.0
	EraEvents.advance(state)
	_check(state.politics[0]["fired_pretender"], "pretender: fires for an ambitious, unsatisfied seated character")
	_check(is_equal_approx(state.politics[0]["pretender_ticks_left"], EraEvents.PRETENDER_CRISIS_TICKS),
		"pretender: opens the crisis window at its full duration")
	_check(state.era_events["last_announcement"] != "", "pretender: sets a last_announcement")


func _test_pretender_does_not_fire_below_ambition_threshold() -> void:
	var state := StrategicState.new()
	state.roster[0]["fleet_commander"]["ambition"] = EraEvents.PRETENDER_AMBITION_THRESHOLD  # exactly at, not above
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 20.0
	EraEvents.advance(state)
	_check(not state.politics[0]["fired_pretender"], "pretender: does not fire at exactly the ambition threshold (strictly above required)")


func _test_pretender_does_not_fire_for_a_satisfied_character() -> void:
	var state := StrategicState.new()
	state.roster[0]["fleet_commander"]["ambition"] = 90.0
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 80.0  # well-satisfied
	EraEvents.advance(state)
	_check(not state.politics[0]["fired_pretender"], "pretender: a satisfied character is not a threat no matter how ambitious")


func _test_pretender_does_not_fire_for_an_unseated_character() -> void:
	var state := StrategicState.new()
	state.roster[0]["genius_officer"]["ambition"] = 90.0  # unseated by default
	EraEvents.advance(state)
	_check(not state.politics[0]["fired_pretender"], "pretender: an unseated character (no political seat to leverage) doesn't trigger this event")


func _test_pretender_fires_only_once() -> void:
	var state := StrategicState.new()
	state.roster[0]["fleet_commander"]["ambition"] = 80.0
	state.politics[0]["seats"]["fleet_commander"]["satisfaction"] = 20.0
	EraEvents.advance(state)
	state.politics[0]["pretender_ticks_left"] = 0.0  # simulate the window having fully decayed
	EraEvents.advance(state)
	_check(is_equal_approx(state.politics[0]["pretender_ticks_left"], 0.0),
		"pretender: does not re-fire (re-open the window) once already spent this campaign")


## --- debt crunch -----------------------------------------------------------------------------

func _test_debt_crunch_gradual_counter_accumulates_and_fires() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_military"] = 0.6  # above DEBT_CRUNCH_MILITARY_THRESHOLD (0.55)
	var materiel_before := 500.0
	state.materiel[0] = materiel_before
	for t in range(int(EraEvents.DEBT_CRUNCH_TICKS_REQUIRED)):
		EraEvents.advance(state)
	_check(state.politics[0]["fired_debt_crunch"], "debt crunch: fires once the counter reaches its requirement")
	_check(is_equal_approx(state.materiel[0], materiel_before * EraEvents.DEBT_CRUNCH_MATERIEL_FRACTION),
		"debt crunch: cuts materiel by exactly the stated fraction")


func _test_debt_crunch_counter_unwinds_gradually_not_hard_reset() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_military"] = 0.6
	for t in range(10):
		EraEvents.advance(state)
	var accumulated: float = state.politics[0]["military_heavy_ticks"]
	_check(is_equal_approx(accumulated, 10.0), "test setup: accumulated 10 ticks' worth of progress")

	state.politics[0]["budget_military"] = 0.2  # dips below threshold for ONE tick
	EraEvents.advance(state)
	_check(is_equal_approx(state.politics[0]["military_heavy_ticks"], 9.0),
		"debt crunch: a single dip below threshold unwinds by exactly one tick's worth, not the whole streak")
	_check(not state.politics[0]["fired_debt_crunch"], "test setup: nowhere near firing yet")


func _test_debt_crunch_fires_only_once() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_military"] = 0.6
	for t in range(int(EraEvents.DEBT_CRUNCH_TICKS_REQUIRED) + 5):
		EraEvents.advance(state)
	var materiel_after_first_fire: float = state.materiel[0]
	for t in range(20):
		EraEvents.advance(state)
	_check(is_equal_approx(state.materiel[0], materiel_after_first_fire),
		"debt crunch: never fires a second time even if military spending stays high indefinitely")


## --- shared threshold_bump / regime interaction --------------------------------------------

func _test_current_threshold_bump_sums_instability_and_pretender() -> void:
	var pol := {"instability_ticks_left": 5.0, "pretender_ticks_left": 5.0}
	_check(is_equal_approx(Removal.current_threshold_bump(pol),
		Removal.INSTABILITY_THRESHOLD_BUMP + Removal.PRETENDER_THRESHOLD_BUMP),
		"current_threshold_bump: sums BOTH sources when both are active")

	var pol_pretender_only := {"instability_ticks_left": 0.0, "pretender_ticks_left": 5.0}
	_check(is_equal_approx(Removal.current_threshold_bump(pol_pretender_only), Removal.PRETENDER_THRESHOLD_BUMP),
		"current_threshold_bump: pretender alone contributes its own bump")

	var pol_neither := {"instability_ticks_left": 0.0, "pretender_ticks_left": 0.0}
	_check(is_equal_approx(Removal.current_threshold_bump(pol_neither), 0.0),
		"current_threshold_bump: exactly 0.0 when neither is active")


func _test_pretender_crisis_blocks_new_regime_actions() -> void:
	var state := StrategicState.new()
	state.politics[0]["pretender_ticks_left"] = 10.0  # active, no instability window
	var seats_before: Dictionary = (state.politics[0]["seats"] as Dictionary).duplicate(true)
	_check(not Regime.purge(state, 0), "pretender crisis: blocks purge the same way an instability window does")
	_check(not Regime.broaden(state, 0), "pretender crisis: blocks broaden")
	_check(not Regime.expand_franchise(state, 0), "pretender crisis: blocks expand_franchise")
	_check(not Regime.restrict_franchise(state, 0), "pretender crisis: blocks restrict_franchise")
	_check(state.politics[0]["seats"] == seats_before, "pretender crisis: every rejected action left seats untouched")


## --- fortress auction -----------------------------------------------------------------------

func _test_fortress_auction_does_not_fire_before_min_tick() -> void:
	var state := StrategicState.new()
	state.tick = int(EraEvents.FORTRESS_AUCTION_MIN_TICK) - 1
	EraEvents.advance_pre_rebellion(state)
	_check(not state.era_events["fired_fortress_auction"], "fortress auction: does not fire before its own minimum tick")
	_check(not is_equal_approx(state.planets[EraEvents.FORTRESS_AUCTION_SYSTEM]["unrest"], Rebellion.REBELLION_THRESHOLD),
		"fortress auction: target system's unrest is untouched before the minimum tick")


## The critical regression test for the design review's central finding:
## stepping the REAL sim must actually produce a REBEL_SIDE flip, not just a
## transient unrest value that erodes away before Rebellion.advance ever
## reads it (which is exactly what the original, buggy pipeline ordering
## would have produced).
func _test_fortress_auction_actually_triggers_a_real_rebellion() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	var target := EraEvents.FORTRESS_AUCTION_SYSTEM
	_check(sim.state.system_owner[target] != Rebellion.REBEL_SIDE, "test setup: the target system starts normally owned")
	var fired_at_tick := -1
	for t in range(int(EraEvents.FORTRESS_AUCTION_MIN_TICK) + 5):
		sim.step(stream)
		if sim.state.system_owner[target] == Rebellion.REBEL_SIDE and fired_at_tick == -1:
			fired_at_tick = sim.state.tick
	_check(sim.state.system_owner[target] == Rebellion.REBEL_SIDE,
		"fortress auction: the target system ACTUALLY rebels (a real REBEL_SIDE flip), not just a transient unrest spike")
	_check(fired_at_tick >= int(EraEvents.FORTRESS_AUCTION_MIN_TICK),
		"fortress auction: the rebellion fires at or after the event's own minimum tick, not before")


func _test_fortress_auction_fires_only_once() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	for t in range(int(EraEvents.FORTRESS_AUCTION_MIN_TICK) + 5):
		sim.step(stream)
	_check(sim.state.era_events["fired_fortress_auction"], "test setup: the event has fired")
	# Retaking/re-losing the system later in a real campaign must never
	# re-trigger this one-shot event -- confirmed by simulating a retake
	# (ownership reset to a normal side) and stepping further.
	sim.state.system_owner[EraEvents.FORTRESS_AUCTION_SYSTEM] = 1
	sim.state.planets[EraEvents.FORTRESS_AUCTION_SYSTEM]["unrest"] = 0.0
	for t in range(20):
		sim.step(stream)
	_check(sim.state.system_owner[EraEvents.FORTRESS_AUCTION_SYSTEM] == 1,
		"fortress auction: does not re-fire and re-flip a system that was retaken after the one-shot event already happened")
