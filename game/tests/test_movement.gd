extends SceneTree
## Headless behavior tests for squadron movement & facing (issue #4, GDD §5.1-5.2).
## Unlike test_determinism.gd (which only cares that hashes are stable), this checks
## the actual kinematics are correct: turning converges without overshoot, cohesion
## drops while turning and regenerates while steady, and moves arrive cleanly. Run:
##   godot --headless --path game --script res://tests/test_movement.gd

const TOL := 0.001

var _failures := 0


func _init() -> void:
	print("test_movement — Godot ", Engine.get_version_info()["string"])

	_test_turn_in_place()
	_test_straight_move_no_turn_cost()
	_test_turn_then_move_arrival()
	_test_cohesion_regen_after_turning()
	_test_order_face_cancels_move()

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


func _spawn(stream: CommandStream, id: String, pos: Vector2, facing: float) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": 0, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": 4, "flag": false,
	}))


## Turning in place (no move target): facing converges to desired at TURN_RATE deg/s,
## the remaining angle never increases, and it holds exactly once reached — no
## overshoot, no oscillation. Pure turning must never translate the squadron.
func _test_turn_in_place() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", Vector2(0, 0), 0.0)
	stream.record(Commands.make(0, "order_face", {"id": "A", "facing": 90.0}))
	var sim := Sim.new(1)

	var per_tick: float = Sim.TURN_RATE / Sim.TICKS_PER_SEC
	var expected_ticks: int = ceili(90.0 / per_tick)

	var prev_diff := 90.0
	var reached_tick := -1
	for t in range(expected_ticks + 5):
		sim.step(stream)
		var facing: float = sim.state.squadrons["A"]["facing"]
		var diff: float = abs(Geometry.normalize_angle(90.0 - facing))
		_check(diff <= prev_diff + TOL, "turn-in-place: remaining angle is non-increasing (tick %d)" % t)
		prev_diff = diff
		if diff <= TOL and reached_tick == -1:
			reached_tick = t

	_check(reached_tick == expected_ticks - 1,
		"turn-in-place: reaches 90° in the expected %d ticks (got tick %d)" %
			[expected_ticks, reached_tick + 1])
	_check(abs(sim.state.squadrons["A"]["facing"] - 90.0) <= TOL,
		"turn-in-place: holds exactly at 90°, no overshoot")
	_check((sim.state.squadrons["A"]["pos"] as Vector2) == Vector2(0, 0),
		"turn-in-place: pure turning never moves the squadron")


## A target already on the nose needs no turning, so cohesion must not drop, and the
## squadron arrives at exactly the tick distance/speed predicts.
func _test_straight_move_no_turn_cost() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", Vector2(0, 0), 0.0)
	stream.record(Commands.make(0, "order_move", {"id": "A", "target": [10, 0]}))
	var sim := Sim.new(1)

	for t in range(200):
		sim.step(stream)
		if sim.state.squadrons["A"]["target"] == null:
			break

	_check(sim.state.squadrons["A"]["cohesion"] >= 100.0 - TOL,
		"straight move: cohesion never drops when already facing the target")
	var pos: Vector2 = sim.state.squadrons["A"]["pos"]
	_check(pos.distance_to(Vector2(10, 0)) <= TOL,
		"straight move: arrives exactly at the target and clears it")

	# Closed-form estimate, ±1 tick: per-tick step distance is SPEED*dt accumulated in
	# float, which can round a hair below the exact per-tick value and cost one extra
	# tick without indicating any real bug — this checks arrival is sane, not
	# bit-exact against a hand-derived formula.
	var expected_ticks: int = ceili(10.0 / (Sim.SPEED / Sim.TICKS_PER_SEC))
	_check(abs(sim.state.tick - expected_ticks) <= 1,
		"straight move: arrival tick is close to distance / speed (got %d, want ~%d)" %
			[sim.state.tick, expected_ticks])


## A target off the nose must be approached by turning first: no meaningful movement
## while badly misaligned, cohesion drops while turning, and it still arrives.
func _test_turn_then_move_arrival() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", Vector2(0, 0), 0.0)
	stream.record(Commands.make(0, "order_move", {"id": "A", "target": [0, 40]}))  # 90° off the nose
	var sim := Sim.new(1)

	sim.step(stream)  # first tick: must turn, must not yet move
	_check((sim.state.squadrons["A"]["pos"] as Vector2) == Vector2(0, 0),
		"turn-then-move: does not move on the very first tick of a 90° reorientation")
	_check(sim.state.squadrons["A"]["cohesion"] < 100.0,
		"turn-then-move: cohesion drops on the turning tick")

	for t in range(300):
		sim.step(stream)
		if sim.state.squadrons["A"]["target"] == null:
			break
	var pos: Vector2 = sim.state.squadrons["A"]["pos"]
	_check(pos.distance_to(Vector2(0, 40)) <= TOL,
		"turn-then-move: eventually arrives at the target despite the initial turn")


## Holding a steady facing (turning finished, or never needed) regenerates cohesion.
func _test_cohesion_regen_after_turning() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", Vector2(0, 0), 0.0)
	stream.record(Commands.make(0, "order_face", {"id": "A", "facing": 90.0}))
	var sim := Sim.new(1)

	for t in range(50):
		sim.step(stream)
	_check(sim.state.squadrons["A"]["cohesion"] < 100.0,
		"cohesion regen: turning left cohesion below full")

	for t in range(200):
		sim.step(stream)
	_check(sim.state.squadrons["A"]["cohesion"] >= 100.0 - TOL,
		"cohesion regen: fully recovers once the squadron holds its new facing")


## A stand-and-turn order supersedes an in-progress move: the target is cleared and
## the squadron must stop translating immediately, not coast or fight the new order.
func _test_order_face_cancels_move() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", Vector2(0, 0), 0.0)
	stream.record(Commands.make(0, "order_move", {"id": "A", "target": [100, 0]}))
	var sim := Sim.new(1)
	for t in range(10):
		sim.step(stream)
	_check((sim.state.squadrons["A"]["pos"] as Vector2).x > 0.0,
		"order_face cancels move: squadron was actually moving first")

	stream.record(Commands.make(sim.state.tick, "order_face", {"id": "A", "facing": 180.0}))
	sim.step(stream)
	_check(sim.state.squadrons["A"]["target"] == null,
		"order_face cancels move: target is cleared the moment the order lands")
	var frozen_pos: Vector2 = sim.state.squadrons["A"]["pos"]

	for t in range(40):  # keep turning all the way around; position must never change
		sim.step(stream)
	_check((sim.state.squadrons["A"]["pos"] as Vector2) == frozen_pos,
		"order_face cancels move: squadron stays put while it turns to the new heading")
