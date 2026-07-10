extends RefCounted
class_name Shipyard
## Materiel stockpiles, shipyards, fleet rebuilding (issue #15, GDD §4.2/§4.4:
## "Industry produces materiel... the universal supply/repair/shipbuilding
## resource"). No planet/industry economy exists yet (that's a bigger future
## system this prototype doesn't need for its own showable outcome) — materiel
## instead accrues passively per owned system, a deliberately simple stand-in
## consistent with GDD §4.2's own solo-dev rule ("no construction queues on
## planets — development changes through policies and events, not
## per-building micromanagement").
##
## "One shipyard per realm": each side's home hub system (Galaxy's A1/B1/C1)
## doubles as its shipyard — a fleet docked there rebuilds lost strength from
## the stockpile, up to its own preset's original max. This is what makes
## "losses matter across battles" real: strength lost in a fight stays lost
## until you can spare the time AND the materiel to sail home and rebuild —
## and if the shipyard itself is threatened or materiel runs dry, it can't
## keep up with losses, which is the whole shape of a war of attrition.

const MATERIEL_PER_STRENGTH := 5.0          # cost to rebuild one strength point
const REBUILD_RATE := 2                     # strength points/tick a dock can absorb, materiel permitting
const SHIPYARDS := {"A1": 0, "B1": 1, "C1": 2}  # system id -> the side whose realm it belongs to


## Passive materiel income, driven by each owned system's planet (issue #17,
## GDD §4.2: "Industry produces materiel... and tax revenue") instead of a flat
## per-system constant — a taxation policy change now visibly moves this same
## number. Derives the set of sides from whatever's actually present in
## system_owner (skipping -1 neutral) rather than a hardcoded [0, 1] — issue #16
## added a 3rd realm, and a fixed 2-side loop here silently starved it of income
## entirely (caught by this file's own test suite once a 3rd side was introduced).
## At every planet's default policy/population, Planet.materiel_output() equals
## exactly Planet.INDUSTRY_BASE (== the old flat constant's value), so a fresh
## campaign's income is unchanged from before this issue existed — only an
## actual policy change (or population drift) moves it.
##
## Issue #18: Rebellion.delivery_mult scales this down further at strikes (50%)
## or stops it entirely at riots ("50% of revenue/materiel/food" / "deliveries
## stop", GDD §4.3) — a REBEL_SIDE-owned system already contributes zero to
## anyone for free via the `side < 0` skip below, so this only matters for a
## planet still owned by a regular side but underperforming.
static func accrue(state: StrategicState) -> void:
	var totals := {}
	for id in state.system_owner.keys():
		var side: int = state.system_owner[id]
		if side < 0:
			continue
		var planet: Dictionary = state.planets[id]
		totals[side] = totals.get(side, 0.0) + Planet.materiel_output(planet) * Rebellion.delivery_mult(planet)
	for side in totals.keys():
		state.materiel[side] = state.materiel.get(side, 0.0) + totals[side]


## Repairs one fleet by up to REBUILD_RATE strength this tick, IF it's docked
## at its own side's shipyard, below its preset's original max strength, and
## its side's materiel stockpile can afford it — silently does nothing
## otherwise (not docked, already at max, or broke).
static func rebuild(state: StrategicState, fleet_id: String) -> void:
	var f: Dictionary = state.fleets[fleet_id]
	var side: int = f["side"]
	if SHIPYARDS.get(f["system"], -1) != side:
		return
	# Issue #16: a shipyard the realm no longer actually OWNS (captured by
	# someone else, see strategic_sim.gd's arrival-capture) must stop
	# rebuilding for its former owner even though the static SHIPYARDS table
	# above still names it theirs — that table is "whose realm built this
	# hub", not "who currently controls it".
	if state.system_owner.get(f["system"], -1) != side:
		return
	var max_strength := FleetPresets.total_strength(f.get("preset", FleetPresets.DEFAULT))
	var missing: int = max_strength - int(f["strength"])
	if missing <= 0:
		return
	var have: float = state.materiel.get(side, 0.0)
	var affordable := int(floor(have / MATERIEL_PER_STRENGTH))
	var actual: int = mini(REBUILD_RATE, mini(missing, affordable))
	if actual <= 0:
		return
	f["strength"] = int(f["strength"]) + actual
	state.materiel[side] = have - actual * MATERIEL_PER_STRENGTH
