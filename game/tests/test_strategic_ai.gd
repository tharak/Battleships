extends SceneTree
## Headless behavior tests for the strategic-level AI (issue #16) — distinct
## from tests/test_battle_ai.gd, which tests the TACTICAL in-battle AI. Run:
##   godot --headless --path game --script res://tests/test_strategic_ai.gd
##
## Layered like the other suites: pure decision-function tests pin down the
## priority order exactly, then a long Sim-integration run plays out the
## issue's own validation question — "does the map create battles that feel
## meaningfully different" — by actually letting a 3-realm campaign run for
## many ticks and checking that territory changes hands and fleets clash, not
## just that individual decisions look right in isolation.

var _failures := 0


func _init() -> void:
	print("test_strategic_ai — Godot ", Engine.get_version_info()["string"])

	_test_my_fleet_finds_the_right_realm()
	_test_winnable_target_requires_a_real_margin()
	_test_winnable_target_finds_a_beatable_fleet()
	_test_winnable_target_ignores_own_side()
	_test_nearest_unowned_finds_a_reachable_system()
	_test_act_rebuilds_when_damaged_and_undocked()
	_test_act_does_not_rebuild_when_already_home()
	_test_act_attacks_a_winnable_target()
	_test_act_expands_when_nothing_is_winnable()
	_test_act_respects_its_own_decision_cadence()
	_test_campaign_produces_territory_changes_and_clashes()

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


## --- pure decision functions ------------------------------------------------------------

func _test_my_fleet_finds_the_right_realm() -> void:
	var state := StrategicState.new()
	state.fleets["Home"] = {"side": 0, "system": "A1"}
	state.fleets["Rival"] = {"side": 1, "system": "B1"}
	_check(StrategicAI._my_fleet(state, 1) == "Rival", "_my_fleet: finds the fleet belonging to the given side")
	_check(StrategicAI._my_fleet(state, 2) == "", "_my_fleet: an empty string when this realm has no fleet at all")


func _test_winnable_target_requires_a_real_margin() -> void:
	var state := StrategicState.new()
	# Roughly even strength -- should NOT read as "winnable" (WIN_MARGIN=1.15
	# requires a real edge, not a coin flip that would look suicidal to attack).
	state.fleets["Mine"] = {"side": 1, "system": "B1", "strength": 75, "supply": 100.0}
	state.fleets["Theirs"] = {"side": 0, "system": "A1", "strength": 74, "supply": 100.0}
	var f: Dictionary = state.fleets["Mine"]
	_check(StrategicAI._winnable_target(state, 1, f) == "",
		"_winnable_target: a roughly even fight is not treated as winnable")


func _test_winnable_target_finds_a_beatable_fleet() -> void:
	var state := StrategicState.new()
	state.fleets["Mine"] = {"side": 1, "system": "B1", "strength": 150, "supply": 100.0}
	state.fleets["Theirs"] = {"side": 0, "system": "A1", "strength": 50, "supply": 100.0}
	var f: Dictionary = state.fleets["Mine"]
	_check(StrategicAI._winnable_target(state, 1, f) == "Theirs",
		"_winnable_target: a fleet with a real power advantage is a legal target")


func _test_winnable_target_ignores_own_side() -> void:
	var state := StrategicState.new()
	state.fleets["Mine"] = {"side": 1, "system": "B1", "strength": 150, "supply": 100.0}
	state.fleets["Friend"] = {"side": 1, "system": "A1", "strength": 5, "supply": 100.0}
	var f: Dictionary = state.fleets["Mine"]
	_check(StrategicAI._winnable_target(state, 1, f) == "",
		"_winnable_target: never targets a fleet on its own side, however weak")


func _test_nearest_unowned_finds_a_reachable_system() -> void:
	var state := StrategicState.new()
	var f := {"side": 1, "system": "B1"}
	var target := StrategicAI._nearest_unowned(state, 1, f)
	# Sector B is entirely owned by side 1 itself -- the nearest system NOT
	# owned by side 1 is in a neighboring sector, reached via one of the two
	# chokepoints (A2 through B2, or C3 through B3).
	_check(target == "A2" or target == "C3",
		"_nearest_unowned: finds the nearest system in a neighboring realm's territory (got %s)" % target)


## --- act() integration -------------------------------------------------------------------
##
## `act()` only RECORDS a command into the stream (same "no direct state pokes"
## discipline as everything else in this codebase) -- it takes a subsequent
## sim.step() call to actually APPLY it and update dest/path. Every test below
## calls step() once more after act() specifically to observe the effect, not
## just that a command was queued.

func _test_act_rebuilds_when_damaged_and_undocked() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B2", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.fleets["F1"]["strength"] = 10  # well below half of preset max (75)
	var ai := StrategicAI.new(1, "B1")
	ai.act(sim.state, stream)
	sim.step(stream)
	var path: Array = sim.state.fleets["F1"]["path"]
	var dest = sim.state.fleets["F1"]["dest"]
	_check((dest == "B1") or (not path.is_empty() and path[-1] == "B1"),
		"act: a damaged, undocked fleet is ordered home to its own shipyard")


func _test_act_does_not_rebuild_when_already_home() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.fleets["F1"]["strength"] = 10
	var ai := StrategicAI.new(1, "B1")
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["dest"] == null,
		"act: already at its own shipyard while damaged issues no pointless order")


func _test_act_attacks_a_winnable_target() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "wedge"}))
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Weak", "side": 0, "system": "A1", "preset": "swarm"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.fleets["Weak"]["strength"] = 5  # make it clearly winnable
	var ai := StrategicAI.new(1, "B1")
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["dest"] != null,
		"act: a winnable target in range gets an attack order, not a hold")


func _test_act_expands_when_nothing_is_winnable() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var ai := StrategicAI.new(1, "B1")
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["dest"] != null,
		"act: with nothing to fight, a healthy fleet still expands toward unowned territory")


func _test_act_respects_its_own_decision_cadence() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var ai := StrategicAI.new(1, "B1")
	ai.act(sim.state, stream)  # decides now, next decision not due for DECISION_PERIOD_TICKS
	sim.step(stream)  # applies that first decision
	_check(sim.state.fleets["F1"]["dest"] != null, "setup: the first decision actually issued an order")

	# Cancel it, then try to force a second, premature decision on the very
	# next tick -- act() should refuse (too soon) and issue nothing new.
	sim.state.fleets["F1"]["dest"] = null
	sim.state.fleets["F1"]["path"] = []
	ai.act(sim.state, stream)
	sim.step(stream)
	_check(sim.state.fleets["F1"]["dest"] == null,
		"act: does not re-decide before its own DECISION_PERIOD_TICKS cadence elapses")


## The issue's own validation question, played out directly: run a real
## 3-realm campaign (all sides AI-controlled, no player orders at all) for
## long enough that a "does nothing ever happen" build would be obviously
## wrong, and check territory actually changes hands and fleets actually
## clash -- not just that the simulation runs without crashing.
func _test_campaign_produces_territory_changes_and_clashes() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "A", "side": 0, "system": "A1", "preset": "line"}))
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "B", "side": 1, "system": "B1", "preset": "line"}))
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "C", "side": 2, "system": "C1", "preset": "line"}))
	var sim := StrategicSim.new()
	var ai_a := StrategicAI.new(0, "A1")  # the "player" is AI-controlled too, for this test only
	var ai_b := StrategicAI.new(1, "B1")
	var ai_c := StrategicAI.new(2, "C1")

	var initial_owners := {}
	for id in sim.state.system_owner.keys():
		initial_owners[id] = sim.state.system_owner[id]

	var any_contact_resolved := false
	for t in range(2000):
		ai_a.act(sim.state, stream)
		ai_b.act(sim.state, stream)
		ai_c.act(sim.state, stream)
		sim.step(stream)
		var contact := BattleBridge.detect_contact(sim.state)
		if not contact.is_empty():
			var fa: Dictionary = sim.state.fleets[contact[0]]
			var fb: Dictionary = sim.state.fleets[contact[1]]
			var result := AutoResolve.resolve(int(fa["strength"]), float(fa["supply"]), int(fb["strength"]), float(fb["supply"]))
			BattleBridge.apply_result(sim.state, contact[0], contact[1], result["a_left"], result["b_left"], fa["system"])
			any_contact_resolved = true

	var territory_changed := false
	for id in initial_owners.keys():
		if sim.state.system_owner[id] != initial_owners[id]:
			territory_changed = true
			break

	_check(any_contact_resolved, "campaign: three independent AI realms eventually clash at least once")
	_check(territory_changed, "campaign: territory actually changes hands over the course of the war")
