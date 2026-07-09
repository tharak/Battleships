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


## Advance exactly one tick: apply commands due this tick, then kinematics, then
## combat. Never call anything else to mutate state — this is the determinism
## contract. Returns this tick's combat events (hits/destructions) so a caller like
## main.gd can render them (e.g. a firing beam) without re-deriving them; nothing
## inside Sim itself depends on the return value.
func step(stream: CommandStream) -> Array:
	for cmd in stream.due(state.tick):
		_apply(cmd)
	var dt := 1.0 / TICKS_PER_SEC
	_advance_kinematics(dt)
	var events := _advance_combat(dt)
	state.tick += 1
	return events


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
				"arrive_facing": null,
				"cohesion": 100.0,
				"dmg_accum": 0.0,
			}
		"order_move":
			if state.squadrons.has(a["id"]):
				var sq: Dictionary = state.squadrons[a["id"]]
				sq["target"] = Commands.array_to_pos(a["target"])
				# Always overwrite (never leave a stale facing goal from an earlier
				# order): absent "face" means "arrive and hold whatever heading
				# travel left you with", same as before this field existed.
				sq["arrive_facing"] = Geometry.normalize_angle(float(a["face"])) if a.has("face") else null
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
			if sq["arrive_facing"] != null:
				sq["desired_facing"] = sq["arrive_facing"]
			continue

		if Geometry.rel_angle(sq["facing"], sq["pos"], target) <= FACE_TOLERANCE:
			# Move straight toward the target (not strictly along `facing`, which is
			# only guaranteed within FACE_TOLERANCE) so distance-to-target shrinks
			# monotonically every tick and arrival is guaranteed to converge cleanly.
			var step_dist: float = minf(SPEED * dt, dist)
			sq["pos"] = sq["pos"] + to_target.normalized() * step_dist


## Beam combat (issue #5): each squadron with a legal target (Combat.pick_target)
## deals continuous damage every tick. Firer and target are both read from live state
## (not a start-of-tick snapshot) — a squadron already hit earlier this same tick by
## another firer is simply weaker for the rest of the tick, which is correct, not a
## bug: within one tick, order is squadron-id order, same as every other pass here.
func _advance_combat(dt: float) -> Array:
	var events := []
	var ids := state.squadrons.keys()
	ids.sort()
	for firer_id in ids:
		if not state.squadrons.has(firer_id):
			continue  # destroyed earlier this same pass
		var firer: Dictionary = state.squadrons[firer_id]
		var target_id := Combat.pick_target(firer_id, firer, state.squadrons)
		if target_id == "":
			continue
		var target: Dictionary = state.squadrons[target_id]
		var fire_mult := 1.0  # morale/waver effectiveness lands in issue #7
		var dmg: float = Combat.damage_this_tick(firer, target, fire_mult, dt)
		var arc := Combat.target_arc(firer["pos"], target)
		target["dmg_accum"] += dmg
		var whole := floori(target["dmg_accum"])
		if whole > 0:
			target["dmg_accum"] -= whole
			target["strength"] = maxi(0, target["strength"] - whole)
		events.append({"type": "hit", "firer": firer_id, "target": target_id, "arc": arc, "dmg": dmg})
		if target["strength"] <= 0:
			var side: int = target["side"]
			var was_flag: bool = target["flag"]
			state.squadrons.erase(target_id)
			events.append({"type": "destroyed", "id": target_id, "side": side, "flag": was_flag})
	return events
