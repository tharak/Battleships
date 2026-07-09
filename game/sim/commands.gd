extends RefCounted
class_name Commands
## Command kinds and (de)serialization for the sim (GDD §11: "all sim mutations flow
## through serialized commands"). Commands are plain Dictionaries so they round-trip
## through JSON without custom marshalling.
##
## Shape: {"t": int tick, "k": String kind, "a": Dictionary args}
##
## Kinds:
##   "spawn"      a: {id, side, pos: [x,y], facing (deg), strength, flag}
##   order_move   a: {id, target: [x,y], face (deg, optional)} -- turns toward and
##                walks to target; if "face" is given, keeps turning to face it after
##                arrival (formation orders use this to land on a slot pointed the
##                right way — see sim/formations.gd)
##   order_face   a: {id, facing (deg)}    -- squadron turns to face in place, holds

const KINDS := ["spawn", "order_move", "order_face"]


static func make(tick: int, kind: String, args: Dictionary) -> Dictionary:
	assert(kind in KINDS, "unknown command kind: %s" % kind)
	return {"t": tick, "k": kind, "a": args}


static func is_valid(cmd: Dictionary) -> bool:
	return cmd.has("t") and cmd.has("k") and cmd.has("a") \
		and typeof(cmd["t"]) == TYPE_INT and cmd["k"] in KINDS \
		and typeof(cmd["a"]) == TYPE_DICTIONARY


## Vector2 isn't JSON-native; commands store positions as 2-element arrays.
static func pos_to_array(p: Vector2) -> Array:
	return [p.x, p.y]


static func array_to_pos(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
