extends RefCounted
class_name Geometry
## Continuous-plane angle math for the battle sim (GDD §5.1: "gameplay is 2D").
## Facing is degrees, 0 = +X axis, increasing counter-clockwise (atan2 convention) —
## this matches Hex.DIR_ANGLE's convention from the Phase 0 paper prototypes, so the
## eventual arc thresholds (front <90°, flank <150°, rear >=150°, GDD §5.5) port over
## with the same numbers, just continuous instead of snapped to 6 hex facings.

static func angle_between(frm: Vector2, to: Vector2) -> float:
	var d := to - frm
	return rad_to_deg(atan2(d.y, d.x))


## Wrap to (-180, 180].
static func normalize_angle(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


## Unsigned angle between a facing direction and the direction to `to` from `frm`.
static func rel_angle(facing: float, frm: Vector2, to: Vector2) -> float:
	return abs(normalize_angle(angle_between(frm, to) - facing))


## Turn `current` toward `target` by at most `max_delta` degrees (either direction,
## shortest way around). Returns the new facing; the caller derives how much was
## actually turned via normalize_angle(new - current) for cohesion cost.
static func turn_toward(current: float, target: float, max_delta: float) -> float:
	var diff := normalize_angle(target - current)
	if abs(diff) <= max_delta:
		return normalize_angle(target)
	return normalize_angle(current + max_delta * signf(diff))
