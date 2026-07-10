extends RefCounted
class_name Rebellion
## Grievance -> unrest -> rebellion escalation pipeline (issue #18, GDD §4.3).
## Builds on strategic/planet.gd's continuous unrest model (issue #17): once
## unrest crosses fixed thresholds, discrete consequences fire -- reduced/
## stopped deliveries, garrison attrition, contagion to lane-adjacent systems,
## and eventually the planet flips to rebel control. Retaking a rebel system
## needs a friendly fleet parked there for a real siege duration, at a real
## strength cost -- not an instant walk-in like ordinary territory capture
## (strategic_sim.gd's _try_capture explicitly excludes REBEL_SIDE systems so
## this can't be bypassed for free -- see that function's docstring).
##
## Scope line (checked against the open-issue list): this is the escalation
## MACHINERY on top of #17's existing unrest number, not new grievance sources
## -- local casualties (#19) and public-goods/governor grievances (need the
## selectorate/commander systems, Phase 4) are deliberately not modeled here.

const REBEL_SIDE := -2   # distinct from -1 (never-claimed neutral). Supply.
                          # owned_hop_path's existing blocking condition
                          # (`owner != side and owner != -1`) already treats
                          # this as hostile territory automatically -- "no
                          # supply transit" (GDD) for free, no supply.gd
                          # change needed. Its own `n != to` destination
                          # exception also means a besieging fleet sitting AT
                          # a rebel system can still be resupplied through
                          # friendly territory up to that system, same as the
                          # existing enemy-system exception -- the siege
                          # doesn't starve itself by construction.

const STRIKE_THRESHOLD := 60.0
const RIOT_THRESHOLD := 75.0
const REBELLION_THRESHOLD := 90.0
const STRIKE_DELIVERY_MULT := 0.5   # "delivers 50% of revenue/materiel/food"
const RIOT_DELIVERY_MULT := 0.0     # "deliveries stop"
const RIOT_GARRISON_ATTRITION := 1.0   # garrison lost/tick while rioting

## Deliberately small: this pushes a LANE-ADJACENT system's raw unrest by this
## much, EVERY tick the source is still actually at "riots" or worse -- GDD
## explicitly wants this to be able to cascade ("Rebellion is contagious...
## a frontier can unzip if ignored"), so two mutually-adjacent rioting systems
## CAN lock each other into a stable, elevated unrest floor above either one's
## own independent policy target (roughly target + RIOT_NEARBY_UNREST_PUSH /
## Planet.UNREST_DRIFT_RATE each, confirmed via a design review's equilibrium
## math) -- that IS the intended mechanic, not a bug. It stays bounded (every
## value clamped [0,100] every tick, confirmed no divergence) and needs real,
## contiguous neglect to trigger at all (a single moderately-taxed planet
## settles near 0 unrest per #17's own tests) -- tuned conservatively so this
## needs genuine neglect across a cluster, not a hair-trigger; see
## test_rebellion.gd's mutual-contagion test for the bounded-equilibrium proof.
const RIOT_NEARBY_UNREST_PUSH := 0.3
const REBELLION_CONTAGION_GRIEVANCE := 15.0  # one-time push to lane-neighbors, the tick a rebellion fires

const SCORCHED_UNREST_FLOOR := 40.0   # a retaken world doesn't start calm or loyal (GDD's
const SCORCHED_LOYALTY_FLOOR := 20.0  # "long-lasting scorched grievance")

const SIEGE_TICKS := 20.0        # consecutive ticks a LONE friendly fleet must hold a rebel system
const SIEGE_STRENGTH_COST := 15  # the besieging fleet's strength cost on a successful retake (floored at 1 -- never wipes it outright)


## "calm" / "strikes" / "riots" / "rebellion" -- pure threshold mapping, not
## stored state (derived on demand, same as Planet's own output functions).
static func escalation_state(unrest: float) -> String:
	if unrest >= REBELLION_THRESHOLD:
		return "rebellion"
	elif unrest >= RIOT_THRESHOLD:
		return "riots"
	elif unrest >= STRIKE_THRESHOLD:
		return "strikes"
	else:
		return "calm"


## Read by Shipyard.accrue (multiplies Planet.materiel_output) and the UI's
## displayed food_output -- "50% of revenue/materiel/food" at strikes, "stops"
## at riots. A REBEL_SIDE-owned system already contributes zero to everyone's
## materiel for free (Shipyard.accrue skips side < 0), so this only matters
## for a planet still owned by a regular side but underperforming.
static func delivery_mult(planet: Dictionary) -> float:
	match escalation_state(planet["unrest"]):
		"riots", "rebellion":
			return RIOT_DELIVERY_MULT
		"strikes":
			return STRIKE_DELIVERY_MULT
		_:
			return 1.0


## One tick's worth of escalation consequences for one system, applied in
## place. Called AFTER Planet.advance (issue #17) so this reads that same
## tick's freshly-drifted unrest, and BEFORE _advance_economy so a fresh
## rebellion/retake this tick is reflected in this same tick's materiel accrual.
static func advance(state: StrategicState, system_id: String) -> Array:
	var events := []
	var owner: int = state.system_owner.get(system_id, -1)
	if owner == REBEL_SIDE:
		_advance_siege(state, system_id, events)
		return events
	if owner < 0:
		return events  # never-claimed neutral ground has no unrest to escalate

	var p: Dictionary = state.planets[system_id]
	var st := escalation_state(p["unrest"])
	if st == "rebellion":
		state.system_owner[system_id] = REBEL_SIDE
		p["siege_progress"] = 0.0
		p["siege_side"] = -1
		events.append({"type": "rebellion", "system": system_id, "former_side": owner})
		for n in Galaxy.neighbors(system_id):
			if state.planets.has(n):
				var np: Dictionary = state.planets[n]
				np["unrest"] = clampf(np["unrest"] + REBELLION_CONTAGION_GRIEVANCE, 0.0, 100.0)
	elif st == "riots":
		p["garrison"] = maxf(0.0, p["garrison"] - RIOT_GARRISON_ATTRITION)
		for n in Galaxy.neighbors(system_id):
			if state.planets.has(n):
				var np: Dictionary = state.planets[n]
				np["unrest"] = clampf(np["unrest"] + RIOT_NEARBY_UNREST_PUSH, 0.0, 100.0)
	return events


## besieger := the SINGLE fleet sitting at system_id (dest == null); "" if zero
## or more than one such fleet is present -- mirrors strategic_sim.gd's own
## _try_capture precedent ("an existing contact resolves on its own" for
## contested presence). No besieger, or the besieger's side changed since last
## tick, resets progress to 0 -- no free partial credit for a siege that was
## abandoned or handed off.
static func _advance_siege(state: StrategicState, system_id: String, events: Array) -> void:
	var p: Dictionary = state.planets[system_id]
	var besieger := _lone_fleet_present(state, system_id)
	if besieger == "":
		p["siege_progress"] = 0.0
		p["siege_side"] = -1
		return
	var f: Dictionary = state.fleets[besieger]
	var side: int = f["side"]
	if int(p["siege_side"]) != side:
		p["siege_progress"] = 0.0
		p["siege_side"] = side
	p["siege_progress"] += 1.0
	if p["siege_progress"] >= SIEGE_TICKS:
		state.system_owner[system_id] = side
		f["strength"] = maxi(1, int(f["strength"]) - SIEGE_STRENGTH_COST)
		p["siege_progress"] = 0.0
		p["siege_side"] = -1
		p["scorched"] = true
		p["unrest"] = SCORCHED_UNREST_FLOOR
		p["loyalty"] = SCORCHED_LOYALTY_FLOOR
		events.append({"type": "retaken", "system": system_id, "side": side})


static func _lone_fleet_present(state: StrategicState, system_id: String) -> String:
	var found := ""
	for id in state.fleets.keys():
		var f: Dictionary = state.fleets[id]
		if f["system"] == system_id and f["dest"] == null:
			if found != "":
				return ""  # more than one fleet present -- no clean siege
			found = id
	return found
