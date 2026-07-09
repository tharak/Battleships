extends RefCounted
class_name Combat
## Beam combat (issue #5, GDD §5.3, §5.5): continuous exchange in forward arcs, with
## flank/rear multipliers on the TARGET's arc. Adapted from the validated Phase 0
## rules (docs/prototypes/battle-rules.md, battle_sim.py) — same front<90°/flank<150°/
## rear thresholds and "seams favor the shooter" tie-break, same "fire only into your
## own front arc" restriction — but continuous DPS instead of per-activation dice,
## since GDD §5.3 explicitly calls for "continuous exchange", not discrete rolls.
##
## Pure functions only; Sim owns when/whether to call them and what to do with the
## results (this keeps combat testable in isolation, see tests/test_combat.gd).

const RANGE := 220.0
## Front-arc baseline damage/sec per point of firer strength. Symmetric TTK for a
## front-on duel is 1/DPS_PER_STRENGTH regardless of strength (firepower AND total
## HP both scale with strength, so they cancel) — this is the number that actually
## sets the game's pace, not the strength value itself. First pass (0.22, tuned
## alongside strength=4) gave a ~4.5s TTK: far too fast for a human to notice a
## losing fight and react. Retuned for a ~27s symmetric TTK instead.
const DPS_PER_STRENGTH := 0.037
const ARC_MULT := {"front": 1.0, "flank": 1.5, "rear": 2.0}  # GDD §5.5: +50% / +100%
const EPS := 1e-9  # seam tie-break, favors the shooter — matches the paper prototype


## Arc of `target` that `firer_pos` is standing in (i.e. what the target exposes to
## the firer) — this is what sets the damage multiplier.
static func target_arc(firer_pos: Vector2, target: Dictionary) -> String:
	var a := Geometry.rel_angle(target["facing"], target["pos"], firer_pos)
	if a < 90.0 - EPS:
		return "front"
	if a < 150.0 - EPS:
		return "flank"
	return "rear"


## A squadron may only fire into its own front arc (the paper rules' hard
## restriction) — this is the firer's-eye check, independent of the target's facing.
static func in_front_arc(firer: Dictionary, target_pos: Vector2) -> bool:
	return Geometry.rel_angle(firer["facing"], firer["pos"], target_pos) <= 90.0 + EPS


## Nearest living enemy this squadron could legally fire at right now (in range, in
## its own front arc), tie-broken by lowest strength then id for full determinism.
## Returns "" if there is no legal target.
static func pick_target(firer_id: String, firer: Dictionary, squadrons: Dictionary) -> String:
	var best_id := ""
	var best_key := [INF, INF]
	var ids := squadrons.keys()
	ids.sort()
	for id in ids:
		if id == firer_id:
			continue
		var sq: Dictionary = squadrons[id]
		if sq["side"] == firer["side"]:
			continue
		var dist: float = (firer["pos"] as Vector2).distance_to(sq["pos"])
		if dist > RANGE:
			continue
		if not in_front_arc(firer, sq["pos"]):
			continue
		var key := [dist, float(sq["strength"])]
		if key[0] < best_key[0] - EPS or (abs(key[0] - best_key[0]) <= EPS and key[1] < best_key[1]):
			best_key = key
			best_id = id
	return best_id


## Damage this firer deals into its target over `dt` seconds, given a fire-rate
## multiplier the caller computes from morale/waver state (1.0 = full effectiveness;
## Combat itself has no opinion on morale — see sim/morale.gd).
static func damage_this_tick(firer: Dictionary, target: Dictionary, fire_mult: float, dt: float) -> float:
	var mult: float = ARC_MULT[target_arc(firer["pos"], target)]
	return DPS_PER_STRENGTH * float(firer["strength"]) * mult * fire_mult * dt


## Nearest living enemy of `sq`, ignoring range and arc (unlike pick_target — this is
## for rout/flee (issue #7, sim/morale.gd), which cares what's dangerous nearby, not
## what's a legal shot). Returns its position, or null if the enemy side has nobody left.
static func nearest_enemy_pos(sq: Dictionary, squadrons: Dictionary):
	var best = null
	var best_dist := INF
	var ids := squadrons.keys()
	ids.sort()
	for id in ids:
		var other: Dictionary = squadrons[id]
		if other["side"] == sq["side"]:
			continue
		var dist: float = (sq["pos"] as Vector2).distance_to(other["pos"])
		if dist < best_dist:
			best_dist = dist
			best = other["pos"]
	return best
