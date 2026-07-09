extends RefCounted
class_name Morale
## Morale, waver, rout (issue #7, GDD §5.5). Continuous 0-100 meter, re-derived from
## the paper prototype's discrete ladder (Steady -> Shaken -> Routed, docs/prototypes/
## battle-rules.md §6) as a real-time drain/regen instead of per-activation d6 checks
## — the same adaptation issue #5 made for combat, for the same reason (RTwP has no
## activations to hang a roll on).
##
## The morale hit triggers on a WHOLE strength point lost, not raw DPS trickle — this
## matches the paper prototype's exact condition ("the squadron lost >=1 Strength
## during an enemy activation") and, just as importantly, scales sensibly against a
## small integer strength pool: charging a flat cost per fractional damage tick would
## either be too small to matter or, scaled up, would rout a squadron from ambient
## chip damage well before it lost any actual ships. The arc penalty reuses
## Combat.ARC_MULT rather than inventing separate flank/rear numbers — "took losses"
## and "flank/rear fire" are the same trigger here, just scaled by the same arc
## multiplier combat already applies to the damage itself: a flank/rear hit that
## draws blood is worse news precisely because it's both a bigger loss and a
## flanking hit, and those two paper drain sources were always tightly correlated
## in practice.
##
## Drain sources implemented (GDD §5.5): taking losses (scaled by arc, as above),
## nearby friendly routs, nearby friendly destruction. NOT implemented here:
## "flagship under fire" (folds into issue #8's command-radius work, since that's
## what defines the flagship's relationship to the fleet) and "low supply" (no
## supply system exists yet — that's a later phase's strategic layer, GDD §4.4).
## "Recovers when disengaged" means any squadron not hit at all this tick
## regenerates, routed or not — that's what makes rallying possible in the first
## place. A squadron taking fire but not yet down a whole point neither costs nor
## regenerates that tick: it's suppressed, not yet demoralized by an actual loss.
##
## `waver` is a pure function of morale (no stored flag: Steady/Wavering is just
## "where morale currently sits", nothing sticky about it). `routed` IS a stored,
## sticky flag — paper's rout has hysteresis (you don't un-rout the instant morale
## ticks up by one point), so it needs real state, not a threshold recomputed fresh
## every tick. The wide gap between ROUT_THRESHOLD (0) and RALLY_THRESHOLD (50)
## is deliberate and does the hysteresis job on its own.

const WAVER_THRESHOLD := 50.0
const RALLY_THRESHOLD := 50.0
const ROUT_THRESHOLD := 0.0

const MORALE_REGEN := 8.0           # morale/sec recovered while not hit at all this tick
## 55, not a smaller number: this needs to rout a squadron after losing HALF its
## strength (2 of 4 points, front-arc), not after nearly all of it. First tuning
## pass used 45 (rout only after 3 of 4 losses) and, tested against the actual demo
## scenario (not just isolated unit scenarios), that left routed squadrons with only
## one strength point of buffer — nowhere near enough to survive the exposed-rear
## flee phase, so "battles end in rout" was actually ending in annihilation instead.
const LOSS_PENALTY := 55.0          # morale lost per whole strength point lost, front-arc baseline
const NEARBY_ROUT_PENALTY := 15.0   # to friendlies in CONTAGION_RADIUS when one routs
const NEARBY_DEATH_PENALTY := 20.0  # to friendlies in CONTAGION_RADIUS when one dies
const CONTAGION_RADIUS := 80.0

const WAVER_FIRE_MULT := 0.5        # "rolls half dice" (paper §6) -> half effectiveness
const ROUTED_FIRE_MULT := 0.0       # a routed squadron does not fire
const ROUT_COHESION_DRAIN := 20.0   # cohesion/sec lost unconditionally while routed
const FLEE_SPEED_MULT := 2.2        # a panicked, all-out run is faster than tactical
                                     # repositioning — "spend all MP fleeing" (paper §6)
                                     # read as a burst of speed, not just a direction


static func is_wavering(sq: Dictionary) -> bool:
	return not sq["routed"] and sq["morale"] < WAVER_THRESHOLD


## What Combat.damage_this_tick should multiply this squadron's output by.
static func fire_multiplier(sq: Dictionary) -> float:
	if sq["routed"]:
		return ROUTED_FIRE_MULT
	if is_wavering(sq):
		return WAVER_FIRE_MULT
	return 1.0


## `strength_lost` is the whole number of strength points this hit actually removed
## this tick (0 if the damage only added to the fractional accumulator) — see
## sim.gd's _advance_combat, which already computes exactly this value.
static func apply_hit(sq: Dictionary, arc: String, strength_lost: int) -> void:
	if strength_lost <= 0:
		return
	var mult: float = Combat.ARC_MULT[arc]
	sq["morale"] = maxf(0.0, sq["morale"] - LOSS_PENALTY * mult * strength_lost)


static func regen(sq: Dictionary, dt: float) -> void:
	sq["morale"] = minf(100.0, sq["morale"] + MORALE_REGEN * dt)


## Returns "routed" if this call is what pushed the squadron into rout, "rallied" if
## it's what brought it back, "" otherwise. The caller (Sim) uses "routed" to fire
## contagion to nearby friendlies.
static func check_transition(sq: Dictionary) -> String:
	if not sq["routed"] and sq["morale"] <= ROUT_THRESHOLD:
		sq["routed"] = true
		sq["target"] = null  # a rout overrides any standing order (GDD §5.5)
		return "routed"
	if sq["routed"] and sq["morale"] >= RALLY_THRESHOLD:
		sq["routed"] = false
		return "rallied"
	return ""


## Friendly squadron ids (same side, alive, not already routed) within
## CONTAGION_RADIUS of `origin_pos` — "a friendly squadron within 2 hexes routs or is
## destroyed" (paper §6), continuous version.
static func contagion_targets(squadrons: Dictionary, side: int, origin_pos: Vector2, exclude_id: String) -> Array[String]:
	var out: Array[String] = []
	var ids := squadrons.keys()
	ids.sort()
	for id in ids:
		if id == exclude_id:
			continue
		var sq: Dictionary = squadrons[id]
		if sq["side"] != side or sq["routed"]:
			continue
		if (sq["pos"] as Vector2).distance_to(origin_pos) <= CONTAGION_RADIUS:
			out.append(id)
	return out
