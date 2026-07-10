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
	_test_path_to_nearest_picks_the_closest_candidate()
	_test_path_to_nearest_empty_when_already_a_candidate()
	_test_path_to_nearest_empty_when_no_candidates()
	_test_visible_systems_includes_own_and_pickets()
	_test_visible_systems_excludes_far_enemy_territory()
	_test_fleet_spawns_and_holds()
	_test_fleet_travels_and_arrives()
	_test_multi_hop_order_completes_both_legs()
	_test_time_controls_pause_stops_ticks()
	_test_fog_of_war_hides_distant_enemy_fleet()
	_test_three_realms_own_their_sectors()
	_test_arrival_captures_neutral_system()
	_test_arrival_captures_undefended_enemy_system()
	_test_friendly_arrival_is_a_capture_no_op()
	_test_simultaneous_opposing_arrival_becomes_contact_not_capture()
	_test_transit_through_captures_intermediate_systems()

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


## battle_bridge.gd's "retreat to the nearest allied planet" -- from B1, A4 and
## A1 are both nominally "Blue territory" candidates, but A1 is 2 hops closer
## via the B2/A2 chokepoint route, so that's the one path_to_nearest must pick.
func _test_path_to_nearest_picks_the_closest_candidate() -> void:
	var path := Galaxy.path_to_nearest("B1", ["A1", "A4"])
	_check(path == ["B2", "A2", "A1"], "path_to_nearest: routes to whichever candidate is actually closer, not the first in the list")


func _test_path_to_nearest_empty_when_already_a_candidate() -> void:
	_check(Galaxy.path_to_nearest("A1", ["A3", "A1"]) == [],
		"path_to_nearest: already standing on a candidate system means no travel needed")


func _test_path_to_nearest_empty_when_no_candidates() -> void:
	_check(Galaxy.path_to_nearest("B1", []) == [],
		"path_to_nearest: no candidates (a wiped-out realm with no systems left) means nowhere to path to")


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


## --- Issue #16: three realms + territory capture --------------------------------------

func _test_three_realms_own_their_sectors() -> void:
	for id in ["A1", "A2", "A3", "A4"]:
		_check(Galaxy.SYSTEMS[id]["owner"] == 0, "sectors: %s belongs to the player (side 0)" % id)
	for id in ["B1", "B2", "B3", "B4"]:
		_check(Galaxy.SYSTEMS[id]["owner"] == 1, "sectors: %s belongs to AI realm 1" % id)
	for id in ["C1", "C2", "C3", "C4"]:
		_check(Galaxy.SYSTEMS[id]["owner"] == 2, "sectors: %s belongs to AI realm 2" % id)


func _test_arrival_captures_neutral_system() -> void:
	var sim := StrategicSim.new()
	sim.state.system_owner["B2"] = -1  # a neutral system, for this test's purposes
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2", "B2"]}))
	for t in range(60):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["system"] == "B2", "capture setup: the fleet actually reached B2")
	_check(sim.state.system_owner["B2"] == 0,
		"arrival capture: arriving at an unowned system with nobody defending it annexes it")


func _test_arrival_captures_undefended_enemy_system() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2", "B2"]}))
	for t in range(60):
		sim.step(stream)
	_check(sim.state.system_owner["B2"] == 0,
		"arrival capture: an enemy-owned system with no fleet actually defending it is annexed the same way")


func _test_friendly_arrival_is_a_capture_no_op() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2"]}))
	for t in range(20):
		sim.step(stream)
	_check(sim.state.system_owner["A2"] == 0,
		"friendly arrival: arriving at a system your own side already owns is a harmless no-op")


## The race the two-pass split in strategic_sim.gd's _advance_fleets exists to
## prevent: two opposing fleets both completing a hop into the same NEUTRAL
## system on the same tick must become a contact, not let whichever fleet id
## happens to sort first quietly win a capture race.
func _test_simultaneous_opposing_arrival_becomes_contact_not_capture() -> void:
	var sim := StrategicSim.new()
	sim.state.system_owner["B1"] = -1
	sim.state.fleets["Alpha"] = {"side": 0, "system": "B2", "dest": "B1", "progress": 0.99, "path": [],
		"supply": 100.0, "preset": "line", "strength": 75}
	sim.state.fleets["Bravo"] = {"side": 1, "system": "B3", "dest": "B1", "progress": 0.99, "path": [],
		"supply": 100.0, "preset": "line", "strength": 75}
	var stream := StrategicCommandStream.new()
	sim.step(stream)
	_check(sim.state.fleets["Alpha"]["system"] == "B1" and sim.state.fleets["Bravo"]["system"] == "B1",
		"simultaneous arrival: both opposing fleets actually complete their hop into B1 this same tick")
	_check(sim.state.system_owner["B1"] == -1,
		"simultaneous arrival: ownership is untouched -- this is a contact, not a capture race")
	var contact := BattleBridge.detect_contact(sim.state)
	_check(contact.size() == 2, "simultaneous arrival: BattleBridge correctly detects this as a same-system contact")


## Intentional consequence, not a bug (see strategic_sim.gd's docstring): a
## multi-hop path's intermediate stops fire "arrived" too, so a fleet threading
## through several undefended systems on its way somewhere else auto-annexes
## all of them along the way.
func _test_transit_through_captures_intermediate_systems() -> void:
	var sim := StrategicSim.new()
	sim.state.system_owner["B2"] = -1
	sim.state.system_owner["B1"] = -1
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1"}))
	stream.record(StrategicCommands.make(0, "order_move", {"id": "F1", "path": ["A2", "B2", "B1"]}))
	for t in range(90):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["system"] == "B1", "transit setup: the fleet reached its final destination")
	_check(sim.state.system_owner["B2"] == 0,
		"transit capture: an undefended intermediate stop is annexed along the way, not just the final destination")
