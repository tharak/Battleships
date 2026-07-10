extends SceneTree
## Headless behavior tests for the grievance -> unrest -> rebellion escalation
## pipeline (issue #18, GDD §4.3). Run:
##   godot --headless --path game --script res://tests/test_rebellion.gd
##
## Layered like the other strategic suites: pure Rebellion function tests pin
## down the thresholds/multipliers exactly, then Sim-integration tests play out
## the issue's own showable outcome -- "a squeezed planet visibly warns,
## strikes, riots, then flips" -- over real ticks, including the two
## integration bugs a design review caught before this shipped: ordinary
## territory capture silently bypassing the siege mechanic, and the strategic
## AI abandoning a siege it just started.

var _failures := 0


func _init() -> void:
	print("test_rebellion — Godot ", Engine.get_version_info()["string"])

	_test_escalation_state_thresholds()
	_test_delivery_mult_by_state()
	_test_accrue_reflects_strikes_and_riots()

	_test_planet_flips_to_rebel_at_the_threshold()
	_test_fresh_rebellion_pushes_neighbors_once()
	_test_riots_drain_garrison_and_nudge_neighbors_each_tick()
	_test_neighbor_nudge_stops_once_the_source_calms_down()
	_test_mutual_riot_contagion_settles_at_a_bounded_equilibrium()

	_test_arrival_does_not_walk_in_capture_a_rebel_system()
	_test_transit_through_a_rebel_system_does_not_capture_it()

	_test_lone_fleet_besieges_and_retakes_a_rebel_system()
	_test_second_fleet_arriving_resets_siege_progress()
	_test_besieger_leaving_resets_siege_progress()

	_test_ai_holds_a_siege_instead_of_wandering_off()

	_test_harshness_includes_taxation_conscription_and_occupation()
	_test_defection_flips_to_a_gentler_neighbor_and_excludes_the_former_ruler()
	_test_defection_needs_a_real_gap_not_a_marginal_one()
	_test_same_side_fleet_freezes_defection_without_resetting_it()
	_test_different_side_fleet_resets_defection_progress()

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


## --- pure Rebellion functions ------------------------------------------------------------

func _test_escalation_state_thresholds() -> void:
	_check(Rebellion.escalation_state(0.0) == "calm", "escalation_state: 0 unrest is calm")
	_check(Rebellion.escalation_state(59.9) == "calm", "escalation_state: just under 60 is still calm")
	_check(Rebellion.escalation_state(60.0) == "strikes", "escalation_state: 60 is strikes")
	_check(Rebellion.escalation_state(74.9) == "strikes", "escalation_state: just under 75 is still strikes")
	_check(Rebellion.escalation_state(75.0) == "riots", "escalation_state: 75 is riots")
	_check(Rebellion.escalation_state(89.9) == "riots", "escalation_state: just under 90 is still riots")
	_check(Rebellion.escalation_state(90.0) == "rebellion", "escalation_state: 90 is rebellion")
	_check(Rebellion.escalation_state(100.0) == "rebellion", "escalation_state: 100 is rebellion")


func _test_delivery_mult_by_state() -> void:
	var p := Planet.default_state()
	p["unrest"] = 0.0
	_check(Rebellion.delivery_mult(p) == 1.0, "delivery_mult: calm delivers in full")
	p["unrest"] = 65.0
	_check(Rebellion.delivery_mult(p) == Rebellion.STRIKE_DELIVERY_MULT, "delivery_mult: strikes deliver at the documented cut")
	p["unrest"] = 80.0
	_check(Rebellion.delivery_mult(p) == Rebellion.RIOT_DELIVERY_MULT, "delivery_mult: riots stop deliveries")


func _test_accrue_reflects_strikes_and_riots() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 65.0  # strikes
	Shipyard.accrue(state)
	# Issue #22: only the military budget share lands in state.materiel.
	var military_frac: float = state.politics[0]["budget_military"]
	var expected := (Planet.INDUSTRY_BASE * Rebellion.STRIKE_DELIVERY_MULT + 3.0 * Planet.INDUSTRY_BASE) * military_frac
	_check(is_equal_approx(state.materiel[0], expected),
		"accrue: a striking planet contributes only its cut, the other 3 owned systems contribute in full")


## --- Planet -> Rebel transition ------------------------------------------------------------

func _test_planet_flips_to_rebel_at_the_threshold() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 95.0
	Rebellion.advance(state, "A1")
	_check(state.system_owner["A1"] == Rebellion.REBEL_SIDE,
		"rebellion: a planet at unrest >= 90 flips ownership to REBEL_SIDE")


func _test_fresh_rebellion_pushes_neighbors_once() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 95.0
	var a2_before: float = state.planets["A2"]["unrest"]
	var a3_before: float = state.planets["A3"]["unrest"]
	Rebellion.advance(state, "A1")
	_check(is_equal_approx(state.planets["A2"]["unrest"], a2_before + Rebellion.REBELLION_CONTAGION_GRIEVANCE),
		"rebellion: a lane-neighbor (A2) takes the one-time contagion grievance")
	# A1's other neighbor, A3, gets it too -- contagion isn't just the first
	# neighbor found.
	_check(is_equal_approx(state.planets["A3"]["unrest"], a3_before + Rebellion.REBELLION_CONTAGION_GRIEVANCE),
		"rebellion: EVERY lane-neighbor takes the contagion push, not just one")


func _test_riots_drain_garrison_and_nudge_neighbors_each_tick() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 80.0  # riots
	state.planets["A1"]["garrison"] = 10.0
	var a2_before: float = state.planets["A2"]["unrest"]
	Rebellion.advance(state, "A1")
	_check(state.planets["A1"]["garrison"] == 10.0 - Rebellion.RIOT_GARRISON_ATTRITION,
		"riots: garrison drains by the documented rate")
	_check(is_equal_approx(state.planets["A2"]["unrest"], a2_before + Rebellion.RIOT_NEARBY_UNREST_PUSH),
		"riots: a lane-neighbor is nudged by the documented (small) amount")


func _test_neighbor_nudge_stops_once_the_source_calms_down() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 80.0
	Rebellion.advance(state, "A1")
	var after_riot: float = state.planets["A2"]["unrest"]
	state.planets["A1"]["unrest"] = 10.0  # source calmed back down, no longer rioting
	Rebellion.advance(state, "A1")
	_check(state.planets["A2"]["unrest"] == after_riot,
		"riots: once the source is no longer rioting, the neighbor stops being pushed at all")


## The real regression for the design review's Finding 4: two mutually-
## adjacent rioting systems (A2 and A1 are lane-neighbors) DO settle at a
## stable, elevated unrest floor above either one's own independent policy
## target (GDD's intended "a frontier can unzip" contagion) -- but it must
## actually be BOUNDED (converge, not diverge to 100 and stay there forever
## regardless of policy) for this to be a feature and not a runaway bug.
func _test_mutual_riot_contagion_settles_at_a_bounded_equilibrium() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["taxation"] = "heavy"
	state.planets["A2"]["taxation"] = "heavy"
	# Kick both above the riot threshold to start the feedback loop.
	state.planets["A1"]["unrest"] = 76.0
	state.planets["A2"]["unrest"] = 76.0
	var last_a1 := 0.0
	for t in range(500):
		Planet.advance(state, "A1")
		Planet.advance(state, "A2")
		Rebellion.advance(state, "A1")
		Rebellion.advance(state, "A2")
		last_a1 = state.planets["A1"]["unrest"]
	_check(last_a1 > 0.0 and last_a1 <= 100.0, "mutual contagion: stays within [0, 100], never diverges")
	# Confirm it actually settled (didn't oscillate/keep climbing) by running
	# further and checking it's stable.
	for t in range(50):
		Planet.advance(state, "A1")
		Planet.advance(state, "A2")
		Rebellion.advance(state, "A1")
		Rebellion.advance(state, "A2")
	_check(is_equal_approx(state.planets["A1"]["unrest"], last_a1),
		"mutual contagion: settles at a genuine stable equilibrium, not still drifting after 500 ticks")


## --- Capture must not bypass the siege -------------------------------------------------

func _test_arrival_does_not_walk_in_capture_a_rebel_system() -> void:
	var sim := StrategicSim.new()
	sim.state.system_owner["A2"] = Rebellion.REBEL_SIDE
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2"]}))
	for t in range(20):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["system"] == "A2", "capture setup: the fleet actually reached A2")
	_check(sim.state.system_owner["A2"] == Rebellion.REBEL_SIDE,
		"rebel capture: arriving at a rebel-held system does NOT instantly annex it -- only a siege can")


func _test_transit_through_a_rebel_system_does_not_capture_it() -> void:
	var sim := StrategicSim.new()
	sim.state.system_owner["A2"] = Rebellion.REBEL_SIDE
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	# A2 is an INTERMEDIATE stop on the way to B2, not the final destination --
	# _try_capture's docstring says intermediate stops fire capture too, so
	# this must be excluded the same way a final destination is.
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2", "B2"]}))
	for t in range(60):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["system"] == "B2", "capture setup: the fleet actually threaded through A2 to B2")
	_check(sim.state.system_owner["A2"] == Rebellion.REBEL_SIDE,
		"rebel capture: threading THROUGH a rebel system on the way elsewhere doesn't annex it either")


## --- Siege / retake ---------------------------------------------------------------------

func _test_lone_fleet_besieges_and_retakes_a_rebel_system() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.fleets["F1"] = {"side": 0, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	var events := []
	for t in range(int(Rebellion.SIEGE_TICKS) - 1):
		events = Rebellion.advance(state, "A2")
	_check(state.system_owner["A2"] == Rebellion.REBEL_SIDE, "siege in progress: not retaken one tick early")
	_check(state.planets["A2"]["siege_progress"] == Rebellion.SIEGE_TICKS - 1.0, "siege in progress: progress accumulated correctly")
	events = Rebellion.advance(state, "A2")
	_check(state.system_owner["A2"] == 0, "siege complete: ownership flips to the besieging side")
	_check(state.fleets["F1"]["strength"] == 75 - Rebellion.SIEGE_STRENGTH_COST,
		"siege complete: the besieging fleet pays the documented strength cost")
	_check(state.planets["A2"]["scorched"], "siege complete: the retaken planet is marked scorched")
	_check(state.planets["A2"]["siege_progress"] == 0.0, "siege complete: progress resets for next time")
	var found_event := false
	for ev in events:
		if ev.get("type") == "retaken":
			found_event = true
	_check(found_event, "siege complete: emits a 'retaken' event")


func _test_second_fleet_arriving_resets_siege_progress() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.fleets["F1"] = {"side": 0, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	for t in range(10):
		Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["siege_progress"] > 0.0, "siege setup: real progress accumulated")
	state.fleets["F2"] = {"side": 1, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["siege_progress"] == 0.0,
		"siege interrupted: a second fleet showing up (contested presence) resets progress to 0")


func _test_besieger_leaving_resets_siege_progress() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.fleets["F1"] = {"side": 0, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	for t in range(10):
		Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["siege_progress"] > 0.0, "siege setup: real progress accumulated")
	state.fleets["F1"]["dest"] = "A1"  # left mid-siege
	Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["siege_progress"] == 0.0,
		"siege abandoned: a besieger that leaves resets progress to 0, no partial credit")


## --- AI holds a siege (the strategic_ai.gd fix a design review required) ----------------

## Places an AI-controlled fleet directly at a rebel system it's already
## besieging and confirms repeated act() calls across several decision cycles
## don't reissue a move order away from it -- without the fix, _nearest_unowned
## would treat the besieged system as fair game (ownership hasn't flipped yet)
## and the AI would abandon every siege before Rebellion.SIEGE_TICKS elapsed.
func _test_ai_holds_a_siege_instead_of_wandering_off() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	sim.state.system_owner["B2"] = Rebellion.REBEL_SIDE
	sim.state.fleets["F1"]["system"] = "B2"
	sim.state.fleets["F1"]["dest"] = null
	sim.state.fleets["F1"]["path"] = []

	var ai := StrategicAI.new(1, "B1")
	var wandered_off := false
	for t in range(30):
		ai.act(sim.state, stream)
		sim.step(stream)
		# Only a problem WHILE the siege is still in progress -- once it
		# completes (ownership flips to side 1), the AI moving on elsewhere is
		# perfectly normal, not "abandoning" anything.
		if sim.state.system_owner.get("B2", -1) == Rebellion.REBEL_SIDE \
				and (sim.state.fleets["F1"]["system"] != "B2" or sim.state.fleets["F1"]["dest"] != null):
			wandered_off = true
	_check(not wandered_off, "AI siege: stays parked at B2 the whole time, never reordered away mid-siege")
	_check(sim.state.system_owner["B2"] == 1,
		"AI siege: given long enough parked in place, the siege actually completes")


## --- Issue #20: occupation stances & planet defection -----------------------------------

func _test_harshness_includes_taxation_conscription_and_occupation() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["taxation"] = "heavy"       # 45
	state.planets["A1"]["conscription"] = "heavy"   # 30
	# A1's native owner is side 0 -- passing owner_override == native excludes
	# occupation (it's not conquered ground relative to that owner).
	_check(is_equal_approx(Rebellion._harshness(state, "A1", 0), 75.0),
		"harshness: native ownership excludes the occupation term (45 tax + 30 conscription)")
	state.planets["A1"]["occupation"] = "plunder"   # 60
	# owner_override == 1 (NOT A1's native owner 0) means this is conquered
	# ground from side 1's point of view -- occupation now applies.
	_check(is_equal_approx(Rebellion._harshness(state, "A1", 1), 135.0),
		"harshness: conquered ownership (owner != native) includes the occupation term too (75 + 60)")


## A2 is native to side 0 (A2-A1 and A2-B2 are both real lanes) -- rebels
## against side 0, and B2 (side 1's own territory, genuinely gentler) is right
## next door. A1 (side 0, the very side A2 just rejected) is ALSO left gentle
## on purpose -- it must never be picked, however low its own harshness is.
func _test_defection_flips_to_a_gentler_neighbor_and_excludes_the_former_ruler() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.planets["A2"]["rebelled_from"] = 0
	state.planets["A2"]["taxation"] = "punitive"     # 75
	state.planets["A2"]["conscription"] = "total"    # 60 -- own_harshness == 135 (native, no occupation)
	state.planets["A2"]["scorched"] = true           # simulate an earlier siege-retake cycle

	state.planets["A1"]["taxation"] = "light"        # gentle, but A1 is side 0 -- must be excluded
	state.planets["A1"]["conscription"] = "volunteer"
	state.planets["B2"]["taxation"] = "light"         # genuinely gentler AND a different side (1)
	state.planets["B2"]["conscription"] = "volunteer" # harshness == 5, gap of 130 >> the margin

	var flipped := false
	for t in range(int(Rebellion.DEFECTION_TICKS) + 5):
		Rebellion.advance(state, "A2")
		if state.system_owner.get("A2", -1) != Rebellion.REBEL_SIDE:
			flipped = true
			break
	_check(flipped, "defection: a rebel planet next to a much gentler neighbor eventually defects")
	_check(state.system_owner["A2"] == 1, "defection: joins the genuinely gentler neighbor (side 1), not the former ruler (side 0)")
	_check(state.planets["A2"]["unrest"] == 20.0 and state.planets["A2"]["loyalty"] == 60.0,
		"defection: gets the RELIEF stat reset, not the siege retake's harsher scorched floor")
	_check(not state.planets["A2"]["scorched"], "defection: clears a stale scorched flag from an earlier siege-retake cycle")
	_check(state.planets["A2"]["rebelled_from"] == -1, "defection: clears rebelled_from on success")
	_check(state.planets["A2"]["occupation"] == "administer", "defection: starts the new owner at a neutral occupation stance")


func _test_defection_needs_a_real_gap_not_a_marginal_one() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.planets["A2"]["rebelled_from"] = 0
	state.planets["A2"]["taxation"] = "heavy"         # 45 + 10 (moderate conscription default) == 55
	state.planets["B2"]["taxation"] = "heavy"         # same harshness (55) -- no gap at all
	for t in range(int(Rebellion.DEFECTION_TICKS) + 5):
		Rebellion.advance(state, "A2")
	_check(state.system_owner["A2"] == Rebellion.REBEL_SIDE,
		"defection: never triggers when no neighbor clears the harshness margin, however long it persists")
	_check(state.planets["A2"]["defection_side"] == -1, "defection: no candidate is ever adopted without a real gap")


func _test_same_side_fleet_freezes_defection_without_resetting_it() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.planets["A2"]["rebelled_from"] = 0
	state.planets["A2"]["taxation"] = "punitive"
	state.planets["A2"]["conscription"] = "total"
	state.planets["B2"]["taxation"] = "light"
	state.planets["B2"]["conscription"] = "volunteer"

	for t in range(10):
		Rebellion.advance(state, "A2")
	var progress_before: float = state.planets["A2"]["defection_progress"]
	_check(progress_before > 0.0, "test setup: real defection progress accumulated toward side 1")

	# A fleet from side 1 -- the SAME side the planet is already defecting
	# toward -- parks there. Progress must freeze, not reset.
	state.fleets["Friendly"] = {"side": 1, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["defection_progress"] == progress_before,
		"same-side fleet: defection progress freezes (siege_progress accumulates instead), not reset to 0")

	state.fleets.erase("Friendly")
	Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["defection_progress"] > progress_before,
		"same-side fleet leaving: defection resumes counting from where it left off")


func _test_different_side_fleet_resets_defection_progress() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = Rebellion.REBEL_SIDE
	state.planets["A2"]["rebelled_from"] = 0
	state.planets["A2"]["taxation"] = "punitive"
	state.planets["A2"]["conscription"] = "total"
	state.planets["B2"]["taxation"] = "light"
	state.planets["B2"]["conscription"] = "volunteer"

	for t in range(10):
		Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["defection_progress"] > 0.0, "test setup: real defection progress accumulated toward side 1")

	# A fleet from side 0 -- NOT the side it's defecting toward -- parks there
	# instead. This is now an active siege, and it cancels the defection.
	state.fleets["Rival"] = {"side": 0, "system": "A2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0, "preset": "line", "strength": 75}
	Rebellion.advance(state, "A2")
	_check(state.planets["A2"]["defection_progress"] == 0.0,
		"different-side fleet: an active siege from a rival side cancels the defection in progress")
	_check(state.planets["A2"]["defection_side"] == -1, "different-side fleet: defection target is cleared too")
