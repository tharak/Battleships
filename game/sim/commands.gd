extends RefCounted
class_name Commands
## Command kinds and (de)serialization for the deterministic sim scaffold
## (GDD §11: "all sim mutations flow through serialized commands"). Commands are
## plain Dictionaries so they round-trip through JSON without custom marshalling.
##
## Shape: {"t": int tick, "k": String kind, "a": Dictionary args}
##
## Kinds implemented for the scaffold (issue #3 — full battle rules are #4-#7):
##   "spawn"      a: {id, side, pos: [col,row], facing, strength, flag}
##   order_move   a: {id, target: [col,row]}   -- squadron walks toward target
##   order_face   a: {id, facing}              -- squadron turns toward facing

const KINDS := ["spawn", "order_move", "order_face"]


static func make(tick: int, kind: String, args: Dictionary) -> Dictionary:
	assert(kind in KINDS, "unknown command kind: %s" % kind)
	return {"t": tick, "k": kind, "a": args}


static func is_valid(cmd: Dictionary) -> bool:
	return cmd.has("t") and cmd.has("k") and cmd.has("a") \
		and typeof(cmd["t"]) == TYPE_INT and cmd["k"] in KINDS \
		and typeof(cmd["a"]) == TYPE_DICTIONARY


## Vector2i isn't JSON-native; commands store positions as 2-element arrays.
static func pos_to_array(p: Vector2i) -> Array:
	return [p.x, p.y]


static func array_to_pos(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
