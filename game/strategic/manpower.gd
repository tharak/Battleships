extends RefCounted
class_name Manpower
## Casualties -> manpower -> loyalty feedback (issue #19, GDD §5.8's battle ->
## strategic contract row: "Crews lost: Drawn from specific planets' manpower
## pools -> local grievances"). Event-driven (called once when a battle
## concludes, from strategic/battle_bridge.gd's apply_result), not a per-tick
## advance() like Planet/Rebellion -- there's nothing to drift, just a one-time
## consequence of a specific fight's losses.
##
## Scope line: GDD's fuller table also mentions "in large-W regimes, bloc-seat
## satisfaction hits" -- needs the selectorate/politics layer (Phase 4), out of
## scope here. This is just the manpower/grievance half.

const CASUALTY_MANPOWER_RATIO := 0.4  # manpower lost per strength-point casualty
const CASUALTY_UNREST_PER_LOSS := 0.3 # unrest gained (one-time) per strength-point casualty


## `side`'s home planet (Shipyard.home_system -- there's no per-fleet
## recruiting-planet field, and strategic_ai.gd already documents "v1 assumes
## exactly one fleet per realm", so the realm's one shipyard IS its one home
## planet) absorbs `casualties` strength worth of losses: manpower drained,
## unrest raised, both real and legible ("a bloody victory that damages the
## home front it recruited from").
##
## Gated on LIVE ownership, not just Shipyard.home_system's static identity —
## mirrors Shipyard.rebuild's own existing precedent for the same table (a
## captured shipyard stops working for its former owner). Without this, a
## realm that's lost its home system entirely (captured by an enemy, or in
## active rebellion) would keep taking direct, un-gated pokes to a planet's
## unrest/manpower it has no actual presence at — and for manpower
## specifically, that poke would silently persist even through a later
## Rebellion retake (unlike unrest, which _advance_siege's retake path resets
## to SCORCHED_UNREST_FLOOR), a real bug a design review caught. A realm that's
## lost its home system already loses fleet rebuild via this same table
## (Shipyard.rebuild) — losing the manpower/grievance feedback too is the same
## "lose your capital, lose the mechanic" shape, not new harshness.
static func apply_casualties(state: StrategicState, side: int, casualties: int) -> void:
	if casualties <= 0:
		return
	var home := Shipyard.home_system(side)
	if state.system_owner.get(home, -1) != side:
		return
	var p: Dictionary = state.planets[home]
	p["manpower"] = maxf(0.0, p["manpower"] - casualties * CASUALTY_MANPOWER_RATIO)
	p["unrest"] = clampf(p["unrest"] + casualties * CASUALTY_UNREST_PER_LOSS, 0.0, 100.0)
