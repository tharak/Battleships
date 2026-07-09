extends RefCounted
class_name Sim
## The only mutation path for battle state (GDD §11: "all sim mutations flow through
## serialized commands from day one — no direct UI-to-sim pokes"). Fixed-tick,
## integer-coordinate, single seeded RNG: this is the scaffold issue #3 exists to
## prove. Placeholder kinematics only — real formations/arcs/morale are #4-#7.

const TICKS_PER_SEC := 10
const MOVE_TICKS := 3  # ticks to cross one hex, matching the paper prototypes' "1 MP/hex"

var state: BattleState


func _init(seed_value: int) -> void:
	state = BattleState.new(seed_value)


## Advance exactly one tick: apply commands due this tick, then step kinematics.
## Never call anything else to mutate state — this is the determinism contract.
func step(stream: CommandStream) -> void:
	for cmd in stream.due(state.tick):
		_apply(cmd)
	_advance_kinematics()
	state.tick += 1


func run_stream(stream: CommandStream, ticks: int) -> void:
	stream.reset_cursor()
	for i in range(ticks):
		step(stream)


func _apply(cmd: Dictionary) -> void:
	var a: Dictionary = cmd["a"]
	match cmd["k"]:
		"spawn":
			# Explicit int()/bool() casts: JSON round-tripping a recorded stream can
			# hand back numbers as float even where the value is logically an int —
			# left uncast, that silently changes the canonical hash after a replay.
			state.squadrons[a["id"]] = {
				"side": int(a["side"]),
				"pos": Commands.array_to_pos(a["pos"]),
				"facing": int(a["facing"]) % 6,
				"strength": int(a["strength"]),
				"flag": bool(a["flag"]),
				"target": null,
				"_move_progress": 0,
			}
		"order_move":
			if state.squadrons.has(a["id"]):
				state.squadrons[a["id"]]["target"] = Commands.array_to_pos(a["target"])
				state.squadrons[a["id"]]["_move_progress"] = 0
		"order_face":
			if state.squadrons.has(a["id"]):
				state.squadrons[a["id"]]["facing"] = int(a["facing"]) % 6


## Placeholder movement: turn to face the target direction, then cross one hex every
## MOVE_TICKS ticks. Deliberately dumb (no arcs, no collision) — proves the sim/render
## boundary and the command pipeline; #4 replaces this with real squadron movement.
func _advance_kinematics() -> void:
	var ids := state.squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = state.squadrons[id]
		var target = sq.get("target")
		if target == null or target == sq["pos"]:
			continue
		var desired := _desired_dir(sq["pos"], target)
		if sq["facing"] != desired:
			sq["facing"] = desired
			sq["_move_progress"] = 0
			continue
		sq["_move_progress"] += 1
		if sq["_move_progress"] >= MOVE_TICKS:
			sq["_move_progress"] = 0
			var nxt: Vector2i = Hex.neighbor(sq["pos"], sq["facing"])
			sq["pos"] = nxt
			if nxt == target:
				sq["target"] = null


static func _desired_dir(frm: Vector2i, to: Vector2i) -> int:
	var ang := Hex.angle_between(frm, to)
	var best := 0
	var best_diff := INF
	for d in range(6):
		var diff = abs(fposmod(Hex.DIR_ANGLE[d] - ang + 180.0, 360.0) - 180.0)
		if diff < best_diff:
			best_diff = diff
			best = d
	return best
