extends SceneTree
## Headless behavior tests for beam combat (issue #5, GDD §5.3/§5.5). Run:
##   godot --headless --path game --script res://tests/test_combat.gd
##
## Layered like test_movement.gd: pure Combat function tests pin down the arc math
## exactly (axis-aligned angles, no trig needed to hand-verify), then Sim-level tests
## check the emergent behavior the showable outcome asks for — positioning visibly
## and numerically wins.

const TOL := 0.001

var _failures := 0


func _init() -> void:
	print("test_combat — Godot ", Engine.get_version_info()["string"])

	_test_target_arc_boundaries()
	_test_in_front_arc_boundaries()
	_test_range_gates_damage()
	_test_front_arc_gates_firing()
	_test_stronger_squadron_wins()
	_test_flank_position_wins_with_no_return_fire()
	_test_destroyed_squadron_is_removed()

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


func _spawn(stream: CommandStream, id: String, pos: Vector2, facing: float, strength := 4) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": 0, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": false,
	}))


func _spawn_side(stream: CommandStream, id: String, side: int, pos: Vector2, facing: float, strength := 4) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": side, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": false,
	}))


## --- pure Combat.target_arc: which arc of the TARGET does the firer stand in ------

func _test_target_arc_boundaries() -> void:
	var target := {"facing": 0.0, "pos": Vector2.ZERO}
	_check(Combat.target_arc(Vector2(50, 0), target) == "front",
		"target_arc: firer dead ahead (bearing 0°) reads front")
	_check(Combat.target_arc(Vector2(-50, 0), target) == "rear",
		"target_arc: firer dead astern (bearing 180°) reads rear")
	_check(Combat.target_arc(Vector2(0, 50), target) == "flank",
		"target_arc: firer abeam (bearing 90°, the front/flank seam) reads flank")
	_check(Combat.target_arc(Vector2(0, -50), target) == "flank",
		"target_arc: firer abeam the other side (bearing -90°) reads flank")


## --- pure Combat.in_front_arc: can the firer legally shoot at all -----------------

func _test_in_front_arc_boundaries() -> void:
	var firer := {"facing": 0.0, "pos": Vector2.ZERO}
	_check(Combat.in_front_arc(firer, Vector2(50, 0)),
		"in_front_arc: target dead ahead is in arc")
	_check(Combat.in_front_arc(firer, Vector2(0, 50)),
		"in_front_arc: target exactly abeam (90°, inclusive seam) is in arc")
	_check(not Combat.in_front_arc(firer, Vector2(-50, 0)),
		"in_front_arc: target dead astern is NOT in arc")


## --- Sim integration ---------------------------------------------------------------

func _test_range_gates_damage() -> void:
	var stream := CommandStream.new()
	_spawn_side(stream, "A", 0, Vector2(0, 0), 0.0)
	_spawn_side(stream, "B", 1, Vector2(Combat.RANGE + 50, 0), 180.0)
	var sim := Sim.new(1)
	for t in range(50):
		sim.step(stream)
	_check(sim.state.squadrons["A"]["strength"] == 4 and sim.state.squadrons["B"]["strength"] == 4,
		"range: squadrons beyond Combat.RANGE never exchange damage")


## Both squadrons face AWAY from each other: each is within the other's range but
## outside the other's front arc, so neither can fire despite being close.
func _test_front_arc_gates_firing() -> void:
	var stream := CommandStream.new()
	_spawn_side(stream, "A", 0, Vector2(100, 0), 0.0)    # faces east, away from B
	_spawn_side(stream, "B", 1, Vector2(0, 0), 180.0)    # faces west, away from A
	var sim := Sim.new(1)
	for t in range(50):
		sim.step(stream)
	_check(sim.state.squadrons["A"]["strength"] == 4 and sim.state.squadrons["B"]["strength"] == 4,
		"front-arc gating: mutually facing away means no legal shot for either side")


## A straight front-vs-front duel: the stronger squadron deals more (damage scales
## with firer strength) and has a bigger HP pool, so it should win outright.
func _test_stronger_squadron_wins() -> void:
	var stream := CommandStream.new()
	_spawn_side(stream, "A", 0, Vector2(0, 0), 0.0, 8)      # strong
	_spawn_side(stream, "B", 1, Vector2(150, 0), 180.0, 2)  # weak, facing squarely at A
	var sim := Sim.new(1)
	for t in range(2000):
		sim.step(stream)
		if not sim.state.squadrons.has("B"):
			break
	_check(not sim.state.squadrons.has("B"), "stronger wins: the weaker squadron is destroyed")
	_check(sim.state.squadrons.has("A") and sim.state.squadrons["A"]["strength"] > 0,
		"stronger wins: the stronger squadron survives")


## The design's key emergent property, worth spelling out: a squadron's front arc is
## a single 180° cone that does double duty — it's both "what I can shoot" and "what
## you see of me if you're standing in it". So exposing your flank/rear to an
## attacker is mathematically inseparable from being unable to fire back at them from
## that angle: target_arc(A, B) and in_front_arc(B, A) are both functions of the same
## (B.facing, B.pos, A.pos) triple, and "front" is a strict subset of "in the firing
## cone". A real flank is therefore always a completely one-sided exchange for that
## pair — which is exactly "position is the biggest damage multiplier" (GDD §5.5).
func _test_flank_position_wins_with_no_return_fire() -> void:
	var stream := CommandStream.new()
	_spawn_side(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	# B sits dead ahead of A (so A can fire), but B's own nose is turned 120° away
	# from the bearing back to A — outside B's own front arc, and (per the note
	# above) therefore also squarely in A's flank/rear view of B.
	var bearing_b_to_a := Geometry.angle_between(Vector2(150, 0), Vector2(0, 0))
	_spawn_side(stream, "B", 1, Vector2(150, 0), Geometry.normalize_angle(bearing_b_to_a - 120.0), 4)
	_check(Combat.target_arc(Vector2(0, 0), sim_dict("B", Vector2(150, 0), bearing_b_to_a - 120.0)) != "front",
		"flank setup sanity: B does not present its front to A")
	var sim := Sim.new(1)
	for t in range(2000):
		sim.step(stream)
		if not sim.state.squadrons.has("B"):
			break
	_check(not sim.state.squadrons.has("B"), "flank: B is destroyed")
	_check(sim.state.squadrons.has("A") and sim.state.squadrons["A"]["strength"] == 4,
		"flank: A takes zero damage — B was never able to fire back")


func sim_dict(_id: String, pos: Vector2, facing: float) -> Dictionary:
	return {"pos": pos, "facing": facing}


func _test_destroyed_squadron_is_removed() -> void:
	var stream := CommandStream.new()
	_spawn_side(stream, "A", 0, Vector2(0, 0), 0.0, 20)
	_spawn_side(stream, "B", 1, Vector2(100, 0), 180.0, 1)
	var sim := Sim.new(1)
	for t in range(200):
		sim.step(stream)
		if not sim.state.squadrons.has("B"):
			break
	_check(not sim.state.squadrons.has("B"), "destruction: a squadron at 0 strength is removed from state")
