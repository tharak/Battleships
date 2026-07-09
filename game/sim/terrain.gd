extends RefCounted
class_name Terrain
## Asteroid field terrain (issue #9, GDD §5.7): "block beam fire, slow movement,
## hide squadrons (ambush setups)". First terrain type on the continuous 2D battle
## plane (GDD §5.1) — modeled as static circular zones, since nothing about this
## phase needs anything richer, and a circle keeps every check (containment, line
## intersection) cheap and exact.
##
## Fields are seeded once at battle start via the "spawn_terrain" command (same
## command-stream discipline as everything else, GDD §11) and never move or change
## — so nothing here mutates state; these are pure geometry queries against whatever
## `terrain: Dictionary` (id -> {kind, pos, radius}) the caller hands in, exactly
## like Combat/Morale/Command's pure-function pattern (see sim/sim.gd's tests/test_
## combat.gd-style split of "pure query" vs "who calls it and what they do next").

const ASTEROID_SPEED_MULT := 0.4      # movement speed inside a field (GDD §5.7 "slows movement")
## An observer must be this close to spot a squadron hidden inside a field (GDD §5.7
## "hide squadrons... ambush setups"). Kept comfortably under Combat.RANGE so a
## concealed squadron can open fire on a target that still can't see it coming.
const ASTEROID_DETECT_RADIUS := 90.0


## The field containing `pos`, or {} if it's clear space. Squadrons are small
## relative to a field, so "is the squadron's point inside" is precise enough — no
## separate squadron radius needed.
static func field_at(pos: Vector2, terrain: Dictionary) -> Dictionary:
	for id in terrain.keys():
		var f: Dictionary = terrain[id]
		if pos.distance_to(f["pos"]) <= f["radius"]:
			return f
	return {}


static func in_field(pos: Vector2, terrain: Dictionary) -> bool:
	return not field_at(pos, terrain).is_empty()


static func speed_mult(pos: Vector2, terrain: Dictionary) -> float:
	return ASTEROID_SPEED_MULT if in_field(pos, terrain) else 1.0


## Closest approach of segment a-b to `center` — standard point-segment projection,
## clamped to the segment's ends.
static func _segment_dist(a: Vector2, b: Vector2, center: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 1e-9:
		return a.distance_to(center)
	var t := clampf((center - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(center)


## True if the straight beam path from `a` to `b` passes through an asteroid field
## that contains NEITHER end — GDD §5.7 "block beam fire". A field either combatant
## is actually standing inside is deliberately excluded: it must not block that
## squadron's own shots in or out (an ambusher hiding in a field firing out is the
## entire point of "hide squadrons for ambush setups" — if a field blocked its own
## occupant's fire, an ambush could never actually deal damage). This only fires for
## a field genuinely sitting in open space between two combatants elsewhere.
static func blocks_line(a: Vector2, b: Vector2, terrain: Dictionary) -> bool:
	for id in terrain.keys():
		var f: Dictionary = terrain[id]
		if a.distance_to(f["pos"]) <= f["radius"] or b.distance_to(f["pos"]) <= f["radius"]:
			continue
		if _segment_dist(a, b, f["pos"]) <= f["radius"]:
			return true
	return false


## Whether `target_pos` is concealed from an observer at `viewer_pos` — GDD §5.7's
## ambush setups: a squadron inside a field is invisible to anything outside
## ASTEROID_DETECT_RADIUS of it. A squadron in open space is never concealed by
## terrain (other concealment sources, if any get added later, are out of scope
## here).
static func is_concealed_from(target_pos: Vector2, viewer_pos: Vector2, terrain: Dictionary) -> bool:
	if not in_field(target_pos, terrain):
		return false
	return viewer_pos.distance_to(target_pos) > ASTEROID_DETECT_RADIUS
