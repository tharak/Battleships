extends SceneTree
## Headless behavior tests for fleet supply (issue #13, GDD §4.4). Run:
##   godot --headless --path game --script res://tests/test_supply.gd
##
## Layered like test_strategic.gd: pure Supply function tests pin down the route/
## throughput math exactly, then Sim-integration tests play out the issue's own
## showable outcome — "cutting a supply lane visibly starves an advancing fleet"
## — over real ticks, not just a single throughput snapshot.

var _failures := 0


func _init() -> void:
	print("test_supply — Godot ", Engine.get_version_info()["string"])

	_test_owned_hop_path_direct()
	_test_owned_hop_path_blocked_by_enemy_territory()
	_test_throughput_full_in_owned_territory()
	_test_throughput_falls_off_per_hop()
	_test_throughput_zero_when_route_blocked()
	_test_raider_reduces_throughput()
	_test_fleet_in_owned_territory_regenerates()
	_test_advancing_fleet_with_intact_chain_survives()
	_test_cutting_the_chain_starves_an_advancing_fleet()
	_test_raider_on_the_route_accelerates_starvation()

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


## --- pure Supply functions ------------------------------------------------------------

func _test_owned_hop_path_direct() -> void:
	var state := StrategicState.new()
	# B2 (neutral, not owned) is a direct neighbor of A2 (owned) -- one real hop.
	var path := Supply.owned_hop_path(state, 0, "B2")
	_check(path == ["B2"], "owned_hop_path: a system directly past owned territory is a single hop")


func _test_owned_hop_path_blocked_by_enemy_territory() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = 1  # enemy seizes the only route out of A-space toward B/C
	var path := Supply.owned_hop_path(state, 0, "B1")
	_check(path.is_empty(),
		"owned_hop_path: no route exists once the only chokepoint out of owned space is enemy-held")


func _test_throughput_full_in_owned_territory() -> void:
	var state := StrategicState.new()
	state.fleets["F1"] = {"side": 0, "system": "A1", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	_check(Supply.throughput(state, "F1") == 1.0,
		"throughput: full (1.0) for a fleet sitting in its own owned territory")


func _test_throughput_falls_off_per_hop() -> void:
	var state := StrategicState.new()
	# B2 is a picket (one hop from owned A2) but not owned -- a real convoy hop.
	state.fleets["F1"] = {"side": 0, "system": "B2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	var t := Supply.throughput(state, "F1")
	_check(absf(t - Supply.HOP_FALLOFF) < 0.001,
		"throughput: exactly one hop's worth of falloff (0.8) one system past owned territory")


func _test_throughput_zero_when_route_blocked() -> void:
	var state := StrategicState.new()
	state.system_owner["A2"] = 1  # same chokepoint seizure as above
	state.fleets["F1"] = {"side": 0, "system": "B1", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	_check(Supply.throughput(state, "F1") == 0.0,
		"throughput: zero once no unbroken owned-territory route exists at all")


func _test_raider_reduces_throughput() -> void:
	var state := StrategicState.new()
	state.fleets["F1"] = {"side": 0, "system": "B2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	var undisturbed := Supply.throughput(state, "F1")
	state.fleets["Raider"] = {"side": 1, "system": "B2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	var raided := Supply.throughput(state, "F1")
	_check(raided < undisturbed and absf(raided - undisturbed * Supply.RAIDER_INTERCEPT) < 0.001,
		"throughput: an enemy fleet parked on the route intercepts a further share (raiding)")


## --- Sim integration: the issue's own showable outcome --------------------------------

func _test_fleet_in_owned_territory_regenerates() -> void:
	var state := StrategicState.new()
	state.fleets["F1"] = {"side": 0, "system": "A1", "dest": null, "progress": 0.0, "path": [], "supply": 50.0}
	for t in range(5):
		Supply.advance(state, "F1")
	_check(state.fleets["F1"]["supply"] > 50.0, "regen: a fleet at home recovers supply over time")


## A short, decisive lunge one hop past the chokepoint, with the chain fully
## intact behind it: the GDD's own contrast case to a starved deep offensive.
func _test_advancing_fleet_with_intact_chain_survives() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "B2"}))
	var sim := StrategicSim.new()
	for t in range(20):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["supply"] > 50.0,
		"intact chain: one hop past owned territory, sitting still, does not starve")


## The issue's literal showable outcome: an enemy holding the chokepoint behind
## an advanced fleet cuts its supply, and it visibly (measurably, over ticks)
## starves -- not just a single throughput reading, the actual meter falling.
func _test_cutting_the_chain_starves_an_advancing_fleet() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "B2"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var before: float = sim.state.fleets["F1"]["supply"]
	_check(before > 50.0, "cut chain setup: the fleet starts healthy while the chain is intact")

	sim.state.system_owner["A2"] = 1  # the enemy seizes the chokepoint behind it
	for t in range(20):
		sim.step(stream)
	var after: float = sim.state.fleets["F1"]["supply"]
	_check(after < before, "cut chain: supply visibly falls once the route home is severed")

	for t in range(60):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["supply"] == 0.0,
		"cut chain: a fully-cut-off fleet keeps starving all the way to zero, not just dipping")


## A moving fleet 2 hops out (B1) has a small positive margin unraided (throughput
## 0.64 * CONVOY_REGEN - (EXISTING_DRAIN+MOVING_DRAIN) = +1.4/tick) but a NEGATIVE
## one once a raider halves that throughput (-1.8/tick) -- exactly the "commerce
## raiding is a real strategy" case: the same route, the same distance, the only
## difference is a raider sitting on it, and that alone flips survive vs. starve.
## Constructs fleet dicts directly (not via spawn_fleet + travel) to pin the
## "currently en route" (dest != null) state precisely, the same way test_morale.gd
## hand-sets state for isolated scenarios rather than percentage-completing a real
## multi-tick maneuver just to get there.
func _test_raider_on_the_route_accelerates_starvation() -> void:
	var unraided_state := StrategicState.new()
	unraided_state.fleets["F1"] = {"side": 0, "system": "B1", "dest": "B3", "progress": 0.0, "path": [], "supply": 50.0}
	for t in range(15):
		Supply.advance(unraided_state, "F1")
	var unraided: float = unraided_state.fleets["F1"]["supply"]

	var raided_state := StrategicState.new()
	raided_state.fleets["F1"] = {"side": 0, "system": "B1", "dest": "B3", "progress": 0.0, "path": [], "supply": 50.0}
	raided_state.fleets["Raider"] = {"side": 1, "system": "B2", "dest": null, "progress": 0.0, "path": [], "supply": 100.0}
	for t in range(15):
		Supply.advance(raided_state, "F1")
	var raided: float = raided_state.fleets["F1"]["supply"]

	_check(unraided > 50.0 and raided < 50.0,
		"raiding: the same route survives unraided but starves once a raider sits on it (%.1f vs %.1f)" %
			[unraided, raided])
