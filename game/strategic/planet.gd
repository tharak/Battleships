extends RefCounted
class_name Planet
## Planet attributes & policy sliders (issue #17, GDD §4.2). Pure-function module,
## same shape as Supply/Shipyard — StrategicState.planets (system id -> Dictionary)
## holds the plain data, this file holds the per-tick formulas.
##
## Scope line (checked against the open-issue list): the grievance/unrest THRESHOLD
## pipeline (strikes at 60, riots at 75, rebellion at 90, contagion) is issue #18.
## Casualties -> manpower feedback is #19. Occupation-stance -> defection is #20.
## This file only makes policies continuously move output/unrest/loyalty/manpower/
## population — no threshold-triggered events yet.
##
## MVP simplification: ONE planet per system (12 total), not GDD's nominal 0-3
## planets/system — continuing this codebase's existing pattern of treating a
## system as the atomic economic unit (see Shipyard.SHIPYARDS).
##
## Planet dict: {population, industry, agriculture: float (rating, not itself
## clamped — industry/agriculture are baseline ratings the deriving functions
## below scale by population), manpower: float (0-MANPOWER_CAP), loyalty: float
## (0-100), unrest: float (0-100), taxation/conscription/occupation: String
## (one of this file's *_LEVELS/*_STANCES), garrison: float (0-manpower, troops
## drawn from the same pool as fleet crews per GDD's "guns vs butter")}.

const POP_BASELINE := 100.0
const POP_CAP := 300.0
const POP_REGROWTH := 0.1          # population/tick baseline regrowth
const INDUSTRY_BASE := 2.0         # == the old flat Shipyard.MATERIEL_PER_SYSTEM_PER_TICK,
                                     # so a fresh, unconquered, default-policy planet
                                     # (population==POP_BASELINE, taxation=="moderate",
                                     # revenue_mult==1.0) reproduces the exact same
                                     # materiel income as before this issue existed.
const AGRICULTURE_BASE := 2.0
const MANPOWER_CAP := 300.0
const MANPOWER_BASE_RATE := 1.0    # manpower/tick gained at conscription mult 1.0, full population
const GARRISON_UPKEEP := 0.02      # manpower/tick drained per garrison point stationed
const GARRISON_SUPPRESS_PER_POINT := 0.5   # unrest-target points cancelled per garrison point
const LOYALTY_UNREST_SUPPRESSION := 40.0   # max unrest-target points cancelled, at loyalty 100
const LOYALTY_DRIFT_RATE := 0.05   # fraction of the gap to loyalty's target closed per tick
const UNREST_DRIFT_RATE := 0.08    # fraction of the gap to unrest's target closed per tick
const HOME_LOYALTY_TARGET := 75.0  # native-owned (not conquered) planets drift here

## light -> punitive: "more revenue now, +unrest" (GDD §4.2). unrest_target is a
## STEADY-STATE contribution (unrest drifts toward it, see advance() below), not a
## per-tick delta — a raw per-tick accumulator has no mean-reversion term and will
## rail-pin at 0/100 well within a campaign's 800-tick cap, permanently defeating
## "policy changes visibly move unrest" (caught by design review before this shipped).
const TAXATION := {
	"light":    {"revenue_mult": 0.6, "unrest_target": 5.0},
	"moderate": {"revenue_mult": 1.0, "unrest_target": 20.0},
	"heavy":    {"revenue_mult": 1.4, "unrest_target": 45.0},
	"punitive": {"revenue_mult": 1.8, "unrest_target": 75.0},
}
const TAXATION_LEVELS := ["light", "moderate", "heavy", "punitive"]

## volunteer -> total: "more manpower, +unrest, -population long-term" (GDD §4.2).
const CONSCRIPTION := {
	"volunteer": {"manpower_mult": 0.5, "unrest_target": 0.0,  "population_drain": 0.0},
	"moderate":  {"manpower_mult": 1.0, "unrest_target": 10.0, "population_drain": 0.05},
	"heavy":     {"manpower_mult": 1.6, "unrest_target": 30.0, "population_drain": 0.15},
	"total":     {"manpower_mult": 2.2, "unrest_target": 60.0, "population_drain": 0.35},
}
const CONSCRIPTION_LEVELS := ["volunteer", "moderate", "heavy", "total"]

## Conquered worlds only (GDD §4.2) -- ignored entirely for a native/home-owned
## planet (see advance() below), where occupation is just an inert seeded field.
const OCCUPATION := {
	"plunder":    {"revenue_mult": 1.5, "unrest_target": 60.0, "loyalty_target": 10.0},
	"administer": {"revenue_mult": 1.0, "unrest_target": 25.0, "loyalty_target": 40.0},
	"integrate":  {"revenue_mult": 0.7, "unrest_target": 5.0,  "loyalty_target": 60.0},
}
const OCCUPATION_STANCES := ["plunder", "administer", "integrate"]


static func default_state() -> Dictionary:
	return {
		"population": POP_BASELINE, "industry": INDUSTRY_BASE, "agriculture": AGRICULTURE_BASE,
		"manpower": 50.0, "loyalty": HOME_LOYALTY_TARGET, "unrest": 0.0,
		"taxation": "moderate", "conscription": "moderate", "garrison": 0.0,
		"occupation": "administer",
		# Issue #18 (Rebellion.gd): siege_progress/siege_side track an in-progress
		# retake of a rebel-owned planet; scorched marks a planet that's BEEN
		# retaken this way. Display-only for v1 -- not read by this file's own
		# advance()/unrest_target formula (a fast-follow, not silently dropped;
		# same honest scope boundary as food_output being display-only below).
		"siege_progress": 0.0, "siege_side": -1, "scorched": false,
	}


## One tick's worth of drift/growth for one planet, applied in place. A system
## nobody owns (owner == -1) is unclaimed ground: no one is imposing policy on it,
## so nothing evolves there yet (also sidesteps needing a "native owner" concept
## for ground that was never anyone's to begin with).
static func advance(state: StrategicState, system_id: String) -> void:
	var owner: int = state.system_owner.get(system_id, -1)
	if owner < 0:
		return
	var p: Dictionary = state.planets[system_id]
	var native: int = Galaxy.SYSTEMS[system_id]["owner"]
	var tax: Dictionary = TAXATION[p["taxation"]]
	var consc: Dictionary = CONSCRIPTION[p["conscription"]]

	# Loyalty tracks WHO rules and HOW, not day-to-day policy severity (GDD keeps
	# loyalty and unrest as separate attributes) -- a native/home planet always
	# drifts toward the same baseline; a conquered one drifts toward its occupier's
	# chosen stance instead.
	var loyalty_target := HOME_LOYALTY_TARGET
	var occ_unrest := 0.0
	if owner != native:
		var occ: Dictionary = OCCUPATION[p["occupation"]]
		loyalty_target = occ["loyalty_target"]
		occ_unrest = occ["unrest_target"]
	p["loyalty"] = p["loyalty"] + (loyalty_target - p["loyalty"]) * LOYALTY_DRIFT_RATE

	var unrest_target: float = clampf(
		tax["unrest_target"] + consc["unrest_target"] + occ_unrest
		- p["garrison"] * GARRISON_SUPPRESS_PER_POINT
		- (p["loyalty"] / 100.0) * LOYALTY_UNREST_SUPPRESSION,
		0.0, 100.0)
	p["unrest"] = p["unrest"] + (unrest_target - p["unrest"]) * UNREST_DRIFT_RATE

	# Manpower deliberately keeps a plain accumulator (not drift-to-target) --
	# nothing in this issue's scope drains it besides garrison upkeep, so it WILL
	# saturate at MANPOWER_CAP under a low garrison. Not a bug: issue #19
	# (casualties -> manpower) is what gives this pool a real ongoing sink.
	var pop_scale: float = p["population"] / POP_BASELINE
	p["manpower"] = clampf(p["manpower"]
		+ MANPOWER_BASE_RATE * consc["manpower_mult"] * pop_scale
		- p["garrison"] * GARRISON_UPKEEP,
		0.0, MANPOWER_CAP)
	p["garrison"] = minf(p["garrison"], p["manpower"])  # never more troops than the pool holds

	p["population"] = clampf(p["population"] + POP_REGROWTH - consc["population_drain"], 0.0, POP_CAP)


## Materiel this planet contributes this tick (Shipyard.accrue sums this per side
## over every system it owns) -- "Industry produces materiel... and tax revenue"
## (GDD §4.2). Population-scaled since GDD calls population out as what "scales
## everything else".
static func materiel_output(planet: Dictionary) -> float:
	var mult: float = TAXATION[planet["taxation"]]["revenue_mult"]
	return planet["industry"] * mult * (planet["population"] / POP_BASELINE)


## Food this planet produces this tick. Nothing in the codebase consumes food yet
## (no fleet-feeding mechanic exists anywhere) -- deliberately just a displayed
## number for now, not wired into a consumption loop, same honesty as Supply.gd's
## own scope notes about what it hasn't built yet.
static func food_output(planet: Dictionary) -> float:
	return planet["agriculture"] * (planet["population"] / POP_BASELINE)
