extends RefCounted
class_name StrategicCommands
## Command kinds for the strategic sim (GDD §11's command-stream rule — same
## discipline as sim/commands.gd, a separate vocabulary because this is a
## separate command stream/sim from the battle layer's, see strategic_state.gd).
##
## Shape: {"t": int tick, "k": String kind, "a": Dictionary args}
##
## Kinds:
##   spawn_fleet   a: {id, side, system, preset (optional, default "line" --
##                 FleetPresets name, issue #14's battle-seeding roster)}
##   order_move    a: {id, path: [system_id, ...]} -- hop sequence to travel,
##                 NOT including the fleet's current system (see
##                 Galaxy.shortest_path, which already returns it in this form)

const KINDS := ["spawn_fleet", "order_move"]


static func make(tick: int, kind: String, args: Dictionary) -> Dictionary:
	assert(kind in KINDS, "unknown strategic command kind: %s" % kind)
	return {"t": tick, "k": kind, "a": args}


static func is_valid(cmd: Dictionary) -> bool:
	return cmd.has("t") and cmd.has("k") and cmd.has("a") \
		and typeof(cmd["t"]) == TYPE_INT and cmd["k"] in KINDS \
		and typeof(cmd["a"]) == TYPE_DICTIONARY
