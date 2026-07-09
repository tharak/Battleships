extends RefCounted
class_name Sim
## The only mutation path for battle state (GDD §11: "all sim mutations flow through
## serialized commands from day one — no direct UI-to-sim pokes"). Fixed-tick, single
## seeded RNG.
##
## Movement & facing (GDD §5.1-5.2, issue #4): a squadron always turns toward its
## `desired_facing` at a limited rate; while it has a move `target`, desired_facing
## tracks the bearing to that target and it advances along its own nose once roughly
## facing it. Cohesion drops while turning hard and regenerates while holding a
## steady course — "formation integrity drops when maneuvering hard" (GDD §5.2).

const TICKS_PER_SEC := 10
const SPEED := 6.0            # plane units / sim-second
const TURN_RATE := 60.0       # degrees / sim-second
const ARRIVE_EPS := 0.05      # snap to target within this distance
const FACE_TOLERANCE := 15.0  # must be within this many degrees of desired_facing to move
const COHESION_TURN_COST := 0.6   # cohesion lost per degree turned
const COHESION_REGEN := 15.0      # cohesion regained per second while not turning

var state: BattleState


func _init(seed_value: int) -> void:
	state = BattleState.new(seed_value)


## Advance exactly one tick: apply commands due this tick, then step kinematics.
## Never call anything else to mutate state — this is the determinism contract.
func step(stream: CommandStream) -> void:
	for cmd in stream.due(state.tick):
		_apply(cmd)
	_advance_kinematics(1.0 / TICKS_PER_SEC)
	state.tick += 1


func run_stream(stream: CommandStream, ticks: int) -> void:
	stream.reset_cursor()
	for i in range(ticks):
		step(stream)


func _apply(cmd: Dictionary) -> void:
	var a: Dictionary = cmd["a"]
	match cmd["k"]:
		"spawn":
			# Explicit int()/float()/bool() casts: JSON round-tripping a recorded
			# stream can hand back numbers as a different numeric type than what was
			# recorded — left uncast, that silently changes the canonical hash after
			# a replay (see the test suite's record->replay assertion).
			var facing := float(a["facing"])
			state.squadrons[a["id"]] = {
				"side": int(a["side"]),
				"pos": Commands.array_to_pos(a["pos"]),
				"facing": facing,
				"desired_facing": facing,
				"strength": int(a["strength"]),
				"flag": bool(a["flag"]),
				"target": null,
				"cohesion": 100.0,
			}
		"order_move":
			if state.squadrons.has(a["id"]):
				state.squadrons[a["id"]]["target"] = Commands.array_to_pos(a["target"])
		"order_face":
			if state.squadrons.has(a["id"]):
				var sq: Dictionary = state.squadrons[a["id"]]
				sq["target"] = null
				sq["desired_facing"] = Geometry.normalize_angle(float(a["facing"]))


func _advance_kinematics(dt: float) -> void:
	var ids := state.squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = state.squadrons[id]
		var target = sq.get("target")

		if target != null:
			sq["desired_facing"] = Geometry.angle_between(sq["pos"], target)

		var before: float = sq["facing"]
		var after: float = Geometry.turn_toward(before, sq["desired_facing"], TURN_RATE * dt)
		var turned: float = abs(Geometry.normalize_angle(after - before))
		sq["facing"] = after

		if turned > 0.0001:
			sq["cohesion"] = maxf(0.0, sq["cohesion"] - COHESION_TURN_COST * turned)
		else:
			sq["cohesion"] = minf(100.0, sq["cohesion"] + COHESION_REGEN * dt)

		if target == null:
			continue

		var to_target: Vector2 = target - sq["pos"]
		var dist: float = to_target.length()
		if dist <= ARRIVE_EPS:
			sq["pos"] = target
			sq["target"] = null
			continue

		if Geometry.rel_angle(sq["facing"], sq["pos"], target) <= FACE_TOLERANCE:
			# Move straight toward the target (not strictly along `facing`, which is
			# only guaranteed within FACE_TOLERANCE) so distance-to-target shrinks
			# monotonically every tick and arrival is guaranteed to converge cleanly.
			var step_dist: float = minf(SPEED * dt, dist)
			sq["pos"] = sq["pos"] + to_target.normalized() * step_dist
