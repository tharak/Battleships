extends SceneTree
## Headless behavior tests for the strategic layer (issue #12, GDD §4.1/§4.6). Run:
##   godot --headless --path game --script res://tests/test_strategic.gd
##
## Layered like the battle layer's suites: pure Galaxy/Intel function tests pin
## down the graph math and fog-of-war exactly, then Sim-integration tests prove
## the issue's own showable outcome — "fleets moving on the strategic map under
## time controls" — end to end.

var _failures := 0


func _init() -> void:
	print("test_strategic — Godot ", Engine.get_version_info()["string"])

	_test_lane_length_symmetric()
	_test_neighbors()
	_test_shortest_path_direct()
	_test_shortest_path_multi_hop()
	_test_shortest_path_same_system()
	_test_shortest_path_prefers_shorter_route()
	_test_visible_systems_includes_own_and_pickets()
	_test_visible_systems_excludes_far_enemy_territory()
	_test_fleet_spawns_and_holds()
	_test_fleet_travels_and_arrives()
	_test_multi_hop_order_completes_both_legs()
	_test_time_controls_pause_stops_ticks()
	_test_fog_of_war_hides_distant_enemy_fleet()

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


## --- pure Galaxy functions -----------------------------------------------------------

func _test_lane_length_symmetric() -> void:
	_check(Galaxy.lane_length("A1", "A2") == Galaxy.lane_length("A2", "A1"),
		"lane_length: symmetric regardless of argument order")


func _test_neighbors() -> void:
	var n := Galaxy.neighbors("A1")
	_check(n.size() == 3 and "A2" in n and "A3" in n and "A4" in n,
		"neighbors: A1's hub connects to all three of its sector's spokes")


func _test_shortest_path_direct() -> void:
	var path := Galaxy.shortest_path("A1", "A2")
	_check(path == ["A2"], "shortest_path: a direct lane is a single hop")


func _test_shortest_path_multi_hop() -> void:
	var path := Galaxy.shortest_path("A1", "B1")
	_check(path == ["A2", "B2", "B1"],
		"shortest_path: crossing the A-B chokepoint takes the hub -> spoke -> chokepoint -> hub route")


func _test_shortest_path_same_system() -> void:
	_check(Galaxy.shortest_path("A1", "A1") == [],
		"shortest_path: a system to itself is an empty path")


func _test_shortest_path_prefers_shorter_route() -> void:
	# A3 is not on the route to B-space at all (only A2 connects onward) -- the
	# path must detour through A1 and A2, not go straight from A3.
	var path := Galaxy.shortest_path("A3", "B1")
	_check(path[0] == "A1" and path[-1] == "B1",
		"shortest_path: routes through the hub when the spoke itself has no chokepoint lane")


## --- pure Intel (pickets fog of war) --------------------------------------------------

func _test_visible_systems_includes_own_and_pickets() -> void:
	var state := StrategicState.new()
	var visible := Intel.visible_systems(state, 0)
	_check(visible.has("A1") and visible.has("A2") and visible.has("A3") and visible.has("A4"),
		"visible_systems: every owned system is visible")
	_check(visible.has("B2"), "visible_systems: one lane beyond an owned system counts as a picket")
	_check(not visible.has("B1"),
		"visible_systems: two lanes beyond an owned system is still fog of war")


func _test_visible_systems_excludes_far_enemy_territory() -> void:
	var state := StrategicState.new()
	var visible := Intel.visible_systems(state, 0)
	_check(not visible.has("C1") and not visible.has("C2"),
		"visible_systems: the enemy's home sector is not visible with no fleet anywhere near it")


## --- Sim integration: the issue's own showable outcome --------------------------------

func _test_fleet_spawns_and_holds() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	var sim := StrategicSim.new()
	sim.run_stream(stream, 5)
	_check(sim.state.fleets["F1"]["system"] == "A1" and sim.state.fleets["F1"]["dest"] == null,
		"spawn: a fleet with no orders holds at its spawn system")


func _test_fleet_travels_and_arrives() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2"]}))
	var sim := StrategicSim.new()
	var arrived_tick := -1
	for t in range(20):
		for ev in sim.step(stream):
			if ev["type"] == "arrived" and ev["id"] == "F1":
				arrived_tick = t
	_check(arrived_tick != -1, "travel: the fleet eventually fires an 'arrived' event")
	_check(sim.state.fleets["F1"]["system"] == "A2",
		"travel: the fleet's system updates to its destination on arrival")
	_check(arrived_tick > 0, "travel: arrival takes a real number of ticks, not instant (proportional to lane length)")


func _test_multi_hop_order_completes_both_legs() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	var path := Galaxy.shortest_path("A1", "B1")
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": path}))
	var sim := StrategicSim.new()
	for t in range(60):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["system"] == "B1",
		"multi-hop: a queued multi-hop order eventually reaches the final destination")


func _test_time_controls_pause_stops_ticks() -> void:
	# "Ticked-pausable" (GDD OQ4, resolved on #12) means the scene's own pause
	# flag simply stops calling step() at all -- there's no separate "paused"
	# sim state to test since Sim itself has no concept of time passing without
	# step() being called. This test just documents/pins that contract: calling
	# step() N times always advances exactly N ticks, regardless of real time.
	var stream := StrategicCommandStream.new()
	var sim := StrategicSim.new()
	for t in range(10):
		sim.step(stream)
	_check(sim.state.tick == 10, "time controls: N step() calls always advances exactly N ticks")


func _test_fog_of_war_hides_distant_enemy_fleet() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Enemy", "side": 1, "system": "C1"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var visible := Intel.visible_systems(sim.state, 0)
	_check(not visible.has(sim.state.fleets["Enemy"]["system"]),
		"fog of war: an enemy fleet sitting deep in enemy territory is not in the player's visible set")
