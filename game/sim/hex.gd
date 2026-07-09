extends RefCounted
class_name Hex
## Hex math: odd-r offset storage, axial cube math for distances/directions.
## Ported 1:1 from prototypes/battle_sim.py so the eventual battle rules behave
## identically to the validated Python/HTML prototypes. Pure functions, no state.

const CUBE_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const DIR_ANGLE: Array[float] = [0.0, -60.0, -120.0, 180.0, 120.0, 60.0]
const SQRT3_2 := 0.8660254037844386  # sqrt(3) / 2


static func to_axial(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x - (pos.y - (pos.y & 1)) / 2, pos.y)


static func from_axial(qr: Vector2i) -> Vector2i:
	return Vector2i(qr.x + (qr.y - (qr.y & 1)) / 2, qr.y)


static func hex_dist(a: Vector2i, b: Vector2i) -> int:
	var aq := to_axial(a)
	var bq := to_axial(b)
	var dq := aq.x - bq.x
	var dr := aq.y - bq.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2.0)


static func neighbor(pos: Vector2i, d: int) -> Vector2i:
	var q := to_axial(pos)
	return from_axial(q + CUBE_DIRS[d])


static func to_cart(pos: Vector2i) -> Vector2:
	return Vector2(pos.x + 0.5 * (pos.y & 1), pos.y * SQRT3_2)


static func angle_between(frm: Vector2i, to: Vector2i) -> float:
	var f := to_cart(frm)
	var t := to_cart(to)
	return rad_to_deg(atan2(t.y - f.y, t.x - f.x))


## Unsigned angle between `frm`'s facing direction (0..5) and the direction to `to`.
static func rel_angle(facing: int, frm: Vector2i, to: Vector2i) -> float:
	var a := angle_between(frm, to) - DIR_ANGLE[facing]
	# fposmod (not fmod) to match Python's always-non-negative `%`.
	a = fposmod(a + 180.0, 360.0) - 180.0
	return abs(a)
