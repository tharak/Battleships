extends SceneTree
## Headless tests for flagship command radius & order delay (issue #8, GDD §5.6).
## Run: godot --headless --path game --script res://tests/test_command.gd
##
## Layered like the other suites: pure Command function tests, Sim integration for
## the morale side (regen bonus, flagship-death shock, permanent penalty), and one
## scene-level test — instantiating the real main.tscn, like test_main_scene.gd —
## for order delay, since that's implemented entirely in main.gd's _command_tick.

const TOL := 0.01

var _failures := 0


func _init() -> void:
	print("test_command — Godot ", Engine.get_version_info()["string"])

	_test_flagship_pos()
	_test_is_in_command_boundary()
	_test_regen_rate()

	_test_in_command_regens_faster()
	_test_flagship_death_shocks_the_fleet()
	_test_flagship_death_permanently_reduces_regen()

	_test_order_delay_outside_command_radius()
	_test_no_delay_inside_command_radius()

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


func _spawn(stream: CommandStream, id: String, side: int, pos: Vector2, facing: float, flag := false, strength := 4) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": side, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": flag,
	}))


## --- pure Command functions ---------------------------------------------------------

func _test_flagship_pos() -> void:
	var squadrons := {
		"A": {"side": 0, "pos": Vector2(10, 0), "flag": false},
		"F": {"side": 0, "pos": Vector2(0, 0), "flag": true},
		"E": {"side": 1, "pos": Vector2(5, 5), "flag": true},
	}
	_check(Command.flagship_pos(0, squadrons) == Vector2(0, 0), "flagship_pos: finds side 0's flagged squadron")
	_check(Command.flagship_pos(1, squadrons) == Vector2(5, 5), "flagship_pos: finds side 1's, independently")
	var no_flag := {"A": {"side": 0, "pos": Vector2(0, 0), "flag": false}}
	_check(Command.flagship_pos(0, no_flag) == null, "flagship_pos: null when the side has no flagship at all")


func _test_is_in_command_boundary() -> void:
	_check(Command.is_in_command(Vector2(0, 0), Vector2(Command.COMMAND_RADIUS, 0)),
		"is_in_command: exactly at the radius counts as inside")
	_check(not Command.is_in_command(Vector2(0, 0), Vector2(Command.COMMAND_RADIUS + 1.0, 0)),
		"is_in_command: just past the radius is outside")
	_check(not Command.is_in_command(Vector2(0, 0), null),
		"is_in_command: no living flagship at all means nothing is ever in command")


func _test_regen_rate() -> void:
	var base := Morale.MORALE_REGEN
	_check(Command.regen_rate(base, false, false) == base, "regen_rate: baseline, no bonus or penalty")
	_check(Command.regen_rate(base, true, false) > base, "regen_rate: in-command bonus increases it")
	_check(Command.regen_rate(base, false, true) < base, "regen_rate: flagship-lost penalty decreases it")
	_check(Command.regen_rate(base, false, true) >= 0.0, "regen_rate: never goes negative")


## --- Sim integration -----------------------------------------------------------------

## Two identical squadrons, one within its flagship's command radius, one just
## outside — otherwise untouched (no combat), so any difference in morale recovery
## is purely the command-radius bonus.
func _test_in_command_regens_faster() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Flag", 0, Vector2(0, 0), 0.0, true)
	_spawn(stream, "Near", 0, Vector2(Command.COMMAND_RADIUS - 10.0, 0), 0.0)
	_spawn(stream, "Far", 0, Vector2(Command.COMMAND_RADIUS + 10.0, 0), 0.0)
	var sim := Sim.new(1)
	sim.step(stream)
	sim.state.squadrons["Near"]["morale"] = 50.0
	sim.state.squadrons["Far"]["morale"] = 50.0
	for t in range(20):
		sim.step(stream)
	_check(sim.state.squadrons["Near"]["morale"] > sim.state.squadrons["Far"]["morale"],
		"command bonus: the in-radius squadron recovers morale faster than the out-of-radius one")


func _test_flagship_death_shocks_the_fleet() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Flag", 0, Vector2(0, 0), 0.0, true, 1)  # 1 strength: dies in one hit
	_spawn(stream, "Far", 0, Vector2(500, 500), 0.0)  # far from the action, never hit itself
	_spawn(stream, "Enemy", 1, Vector2(50, 0), 180.0, false, 20)  # heavy firepower, kills Flag fast
	var sim := Sim.new(1)
	var far_morale_before := 100.0
	var shocked := false
	for t in range(200):
		var events := sim.step(stream)
		for ev in events:
			if ev["type"] == "flagship_lost" and ev["side"] == 0:
				shocked = true
		if shocked:
			break
	_check(shocked, "flagship shock: a flagship_lost event fires when the flagship dies")
	_check(sim.state.squadrons["Far"]["morale"] < far_morale_before,
		"flagship shock: a squadron far from the fight still takes the fleet-wide morale hit")
	_check(sim.state.fleets[0]["flagship_lost"],
		"flagship shock: the side's flagship_lost flag is set")


func _test_flagship_death_permanently_reduces_regen() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Flag", 0, Vector2(0, 0), 0.0, true, 1)
	_spawn(stream, "Survivor", 0, Vector2(500, 500), 0.0)
	_spawn(stream, "Enemy", 1, Vector2(50, 0), 180.0, false, 20)
	var sim := Sim.new(1)
	for t in range(200):
		sim.step(stream)
		if sim.state.fleets[0]["flagship_lost"]:
			break
	_check(sim.state.fleets[0]["flagship_lost"], "permanent penalty: flagship is confirmed lost")
	sim.state.squadrons["Survivor"]["morale"] = 50.0
	var before: float = sim.state.squadrons["Survivor"]["morale"]
	for t in range(10):
		sim.step(stream)
	var after: float = sim.state.squadrons["Survivor"]["morale"]
	var recovered := after - before
	var expected_without_penalty := Morale.MORALE_REGEN * 10.0 * (1.0 / Sim.TICKS_PER_SEC)
	_check(recovered < expected_without_penalty,
		"permanent penalty: regen after flagship loss is slower than the un-penalized baseline")


## --- scene-level: order delay is implemented in main.gd, not Sim ------------------

func _test_order_delay_outside_command_radius() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var main := scene.instantiate()
	get_root().add_child(main)
	main._ready()
	main._sim.step(main._stream)  # apply tick-0 spawns

	var far_id := ""
	var flag_pos: Vector2 = Command.flagship_pos(0, main._sim.state.squadrons)
	for id in main._sim.state.squadrons.keys():
		var sq: Dictionary = main._sim.state.squadrons[id]
		if sq["side"] == 0 and not sq["flag"]:
			far_id = id
			break
	_check(far_id != "", "order delay setup: found a non-flagship blue squadron to test with")

	# Force it far outside its own flagship's command radius, then issue an order.
	main._sim.state.squadrons[far_id]["pos"] = flag_pos + Vector2(Command.COMMAND_RADIUS + 500.0, 0)
	var sel1: Array[String] = [far_id]
	main._selected = sel1
	main._issue_group_move(Vector2(999, 999))

	var immediate_target = main._sim.state.squadrons[far_id]["target"]
	_check(immediate_target == null,
		"order delay: an out-of-command order has NOT landed on the very next check")

	for t in range(Command.ORDER_DELAY_TICKS + 5):
		main._sim.step(main._stream)
	_check(main._sim.state.squadrons[far_id]["target"] != null,
		"order delay: the order eventually lands once its delayed tick arrives")

	main.free()


func _test_no_delay_inside_command_radius() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var main := scene.instantiate()
	get_root().add_child(main)
	main._ready()
	main._sim.step(main._stream)

	var flag_pos: Vector2 = Command.flagship_pos(0, main._sim.state.squadrons)
	var near_id := ""
	for id in main._sim.state.squadrons.keys():
		var sq: Dictionary = main._sim.state.squadrons[id]
		if sq["side"] == 0 and not sq["flag"]:
			near_id = id
			break
	main._sim.state.squadrons[near_id]["pos"] = flag_pos + Vector2(50, 0)  # well inside COMMAND_RADIUS
	var sel2: Array[String] = [near_id]
	main._selected = sel2
	main._issue_group_move(Vector2(999, 999))
	main._sim.step(main._stream)
	_check(main._sim.state.squadrons[near_id]["target"] != null,
		"no delay: an in-command order lands on the very next tick")

	main.free()
