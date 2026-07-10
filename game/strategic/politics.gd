extends RefCounted
class_name Politics
## Selectorate core (issue #22, GDD §4.5) -- the foundation of the Phase 4
## political layer. Every realm has a coalition of essential seats (S3-12 seats,
## W = seats.size()) and a three-way budget slider (military / private /
## public) that splits the realm's tick revenue. Individual seats (small-W
## cronies) are satisfied ONLY by private goods; bloc seats (mass
## constituencies) are satisfied ONLY by public goods, which also lowers
## owned planets' unrest -- "moving the budget slider visibly moves seat
## satisfaction and planet grievances in opposite directions" (the issue's own
## showable outcome). Pure-function module, same shape as Planet/Shipyard/
## Rebellion/Manpower.
##
## Scope line (checked against the open-issue list): this is ONLY seats +
## satisfaction + the budget slider + private/public goods effects. Removal-
## crisis firing/survival threshold is #23; regime actions (purge/broaden/
## franchise) are #24; seats becoming full characters via a shared officer/
## essential roster is #25; AI budget decisions are #26; randomized starts are
## #27. `weight` and `s_percent` are stored here but not yet READ by any
## formula -- #23's replaceability (S / W) and survival-threshold math is what
## consumes them, same "ship the field, document the gap" precedent as issue
## #18's `scorched`/#20's `rebelled_from`.
##
## Individual <-> private, bloc <-> public is a fully symmetric, rigid split:
## GDD explicitly says public goods is "the ONLY thing that satisfies
## bloc-type seats," but never explicitly zeroes out individuals' response to
## public goods, nor restricts private goods to individuals-only ("divided
## among your essential seats" -- plural, undifferentiated). Shipping the
## rigid split anyway as a deliberate MVP simplification (avoids an
## unvalidated cross-term with no consumer yet) -- an authorial choice, not a
## strict reading of the text, so a later issue doesn't mistake it for settled
## canon.
##
## Deliberately NOT touching the battle-layer morale/crew-quality contract row
## GDD's §5.8 table also lists ("Base morale (public-goods level)") -- a real,
## later coupling (arguably #25/#26 territory once the roster/AI exist to make
## it meaningful), logged as a scope boundary, not silently dropped.

const SATISFACTION_DRIFT_RATE := 0.1
# private_per_seat and public_per_capita land in very different numeric
# ranges (dividing by a handful of seats vs. hundreds of population), so
# their scales are NOT expected to match -- tuned empirically via a live
# StrategicSim probe against this file's actual default seed/revenue, not
# guessed from GDD prose alone (same practice already used for Planet's/
# Rebellion's constants).
const PRIVATE_GOODS_SATISFACTION_SCALE := 150.0
const PUBLIC_GOODS_SATISFACTION_SCALE := 10000.0
const PUBLIC_GOODS_UNREST_RELIEF_SCALE := 200.0

const BUDGET_STEP := 0.05  # strategic_map.gd's M/P/G keys shift the split by this much


static func default_state() -> Dictionary:
	return {
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 60.0, "weight": 3.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"veterans_league": {"name": "Veterans' League", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"industrial_bloc": {"name": "Industrial Bloc", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"colonial_assembly": {"name": "Colonial Assembly", "kind": "bloc", "satisfaction": 60.0, "weight": 3.0},
		},
		"s_percent": 20.0,
		"budget_military": 0.4, "budget_private": 0.3, "budget_public": 0.3,
		# Issue #23 (removal.gd): election_countdown ticks down between scheduled
		# elections for large-W realms (plain literal matching Removal.
		# ELECTION_PERIOD_TICKS by value, same "no cross-file constant reference
		# in default_state()" precedent as siege_progress/rebelled_from above);
		# removed_flag/removal_reason mark a realm whose ruler has just been
		# removed from power (a coup or a lost election) -- display-only for
		# every side except the player, whom strategic_map.gd checks this for.
		"election_countdown": 52.0, "removed_flag": false, "removal_reason": "",
		# Issue #24 (regime.gd/removal.gd): instability_ticks_left is a shared
		# cooldown + threshold-easing window opened by any regime action;
		# coup_insurance_debt is a slowly-decaying tax on effective_support that
		# compounds with purge frequency (removal.gd's own watch-item fix);
		# next_seat_id is broaden()'s monotonic counter for synthesizing a
		# collision-free new seat key, surviving any later purge of that or any
		# other seat. Plain literals, same "no cross-file constant reference in
		# default_state()" precedent as election_countdown above.
		"instability_ticks_left": 0.0, "coup_insurance_debt": 0.0, "next_seat_id": 0,
	}


## Population summed across `side`'s currently-owned planets, floored at 1.0 --
## a side owning zero systems would otherwise divide by zero -> NaN, which is
## sticky under addition and would silently wreck that realm's state.materiel
## forever the next time accrue() multiplies by a NaN budget fraction (a
## design review caught this exact risk in a sibling function; guarded the
## same way here defensively).
static func _owned_population(state: StrategicState, side: int) -> float:
	var total := 0.0
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			total += state.planets[id]["population"]
	return maxf(1.0, total)


## One tick's worth of coalition drift for one realm, given this tick's raw
## revenue (Shipyard.accrue's return value, BEFORE the budget split -- accrue
## itself only credits state.materiel with the military share; this function
## is what the private/public shares actually buy). Safe to call for a side
## that currently owns zero systems (revenue will be 0, seats correctly drift
## toward unhappy targets instead of freezing -- see strategic_sim.gd's
## _advance_economy for why this must be driven by state.politics.keys(), not
## by whichever sides happen to appear in accrue()'s returned totals).
static func advance(state: StrategicState, side: int, revenue: float) -> void:
	var pol: Dictionary = state.politics[side]
	var seat_count: int = pol["seats"].size()
	# GDD: "Effectiveness per seat = private budget / number of seats -- this
	# is why small coalitions are cheap and broadening dilutes every crony's
	# cut." Denominator is the WHOLE coalition (individual + bloc), even
	# though only individual seats benefit below -- that's the literal
	# dilution mechanic, not a simplification of it.
	var private_per_seat: float = (revenue * pol["budget_private"]) / maxf(1.0, float(seat_count))
	var public_per_capita: float = (revenue * pol["budget_public"]) / _owned_population(state, side)
	for seat in pol["seats"].values():
		var target: float
		if seat["kind"] == "individual":
			target = clampf(private_per_seat * PRIVATE_GOODS_SATISFACTION_SCALE, 0.0, 100.0)
		else:
			target = clampf(public_per_capita * PUBLIC_GOODS_SATISFACTION_SCALE, 0.0, 100.0)
		seat["satisfaction"] += (target - seat["satisfaction"]) * SATISFACTION_DRIFT_RATE
	_apply_public_goods_to_planets(state, side, public_per_capita)


## GDD: "Public goods... Lowers grievances everywhere (§4.3)." Mirrors
## Rebellion.gd's own contagion-push precedent -- a direct, clamped poke to
## unrest applied from OUTSIDE planet.gd, not a rewrite of Planet.advance's
## own unrest_target formula. Safe against REBEL_SIDE(-2)/neutral(-1): the
## `== side` check can never match either, so a rebel or unowned system is
## automatically excluded, no special-casing needed.
##
## Same-tick ordering (strategic_sim.gd's step() runs this, via
## _advance_economy, AFTER _advance_rebellion): a rebellion decided this tick
## already happened before this poke runs, so relief can never retroactively
## cancel an already-decided rebellion. A planet retaken or defected THIS same
## tick (fresh SCORCHED_UNREST_FLOOR/relief-reset values from Rebellion.gd) IS
## already owned by its new side by the time this runs, so it DOES shave a
## small amount off that fresh value before it's ever observed at its nominal
## number -- a real but minor, bounded (one tick's worth) effect, logged here
## rather than guarded against, same "known ordering edge case" convention as
## `scorched`/`rebelled_from`.
static func _apply_public_goods_to_planets(state: StrategicState, side: int, public_per_capita: float) -> void:
	var relief := public_per_capita * PUBLIC_GOODS_UNREST_RELIEF_SCALE
	if relief <= 0.0:
		return
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			var p: Dictionary = state.planets[id]
			p["unrest"] = maxf(0.0, p["unrest"] - relief)
