extends RefCounted
class_name Roster
## Patronage: command assignment as private goods (issue #25, GDD §6). "One
## roster serves both systems" — the officers who fight battles and the
## essentials who hold political seats are drawn from the same pool.
## Command assignment is itself a private good: give the fleet to a seated
## crony and buy their satisfaction at the price of their competence; give
## it to an unseated "low-born genius" and win battles while the coalition
## seethes at the snub. Pure-function module, same shape as Planet/Rebellion/
## Politics/Removal/Regime. Event-driven for battle consequences (ambition,
## permadeath) — no per-tick advance() at all, same shape as
## strategic/manpower.gd's apply_casualties (nothing to drift, just one-time
## consequences of a specific fight).
##
## Scope, trimmed the same way every Phase 4 issue has been: ~30 GDD traits
## are CUT (no consumer exists, not needed for this issue's showable
## outcome). A randomized/balanced 15-25-character roster (GDD's full range)
## is CUT — this ships a small, hand-authored 6-per-realm default seed
## (matching politics.gd's own default_state() precedent); full randomized
## generation is issue #27's job ("start generator"). A full ambition-driven
## coup mechanic is mostly CUT (that needs an AI to actually decide when to
## pay/promote/purge in response to a threat — issue #26's job) — but
## ambition_threat_penalty below (consumed by removal.gd) gives ambition one
## real, minimal, felt consequence within this issue's own scope, rather
## than leaving it purely decorative.
##
## Roster <-> seats linkage: GDD's named characters map onto politics.gd's
## INDIVIDUAL seats only (fleet_commander/interior_minister/treasury_minister)
## -- bloc seats are impersonal mass constituencies with no one body, the
## same rigid individual<->private/bloc<->public split politics.gd's own
## docstring already documents as a deliberate authorial choice. One
## character per individual seat (same key for character id and seat id),
## plus 3 extra unseated officer candidates -- 6 total per realm.
##
## `logistics` is stored on every character but deliberately NOT consumed by
## any formula in this issue -- "ship the field, document the gap," same
## precedent as #22's weight/s_percent -- a natural fit for a later
## Supply.gd pass, not required by this issue's showable outcome.

const DEFAULT_COMMANDER_ID := "fleet_commander"
## Chosen so the DEFAULT assigned commander (fleet_commander, seeded at
## exactly this value below) is an exact 1.0x battle multiplier -- confirmed
## against test_battle_bridge.gd's own exact-value assertions, which hand-
## build a fleet dict with NO commander_id key at all and expect the
## pre-#25 uptime numbers unchanged.
const BASELINE_TACTICS := 50.0

const COMMAND_SATISFACTION_BONUS := 10.0  # matches the scale of Regime's own pokes (PURGE_PANIC=5, etc.)
const SNUB_PENALTY := 8.0                 # every other seated individual seat, on an UNSEATED appointment

## tactics=80 (the seeded genius) -> ~+18% uptime; tactics=20 -> ~-18% --
## comparable in magnitude to the existing crew-quality swing (~0.8-1.15x,
## strategic/battle_bridge.gd's _crew_quality), so the two factors read as
## peers, neither dwarfing the other. Hard-clamped (issue #24's design
## review lesson: never ship an unbounded bonus/penalty formula).
const TACTICS_UPTIME_SCALE := 0.006
const TACTICS_UPTIME_MIN := 0.5
const TACTICS_UPTIME_MAX := 1.5

const AMBITION_PER_VICTORY := 5.0

## "A brilliant, unsatisfied, ambitious admiral is a coup seed" (GDD §6),
## read literally: a seated character counts as a live threat only once
## their ambition clears this floor AND their own seat's satisfaction is
## genuinely low. Capped total (MAX_AMBITION_THREAT_PENALTY) regardless of
## how many characters qualify, same clamping discipline as every other
## formula this pass -- consumed by removal.gd's effective_support.
const AMBITION_THREAT_THRESHOLD := 60.0
const AMBITION_THREAT_SATISFACTION_CEILING := 40.0
const AMBITION_THREAT_PENALTY := 5.0
const MAX_AMBITION_THREAT_PENALTY := 15.0


static func default_state() -> Dictionary:
	return {
		# Seated -- one per INDIVIDUAL seat (politics.gd's default_state()).
		# fleet_commander's tactics is exactly BASELINE_TACTICS: see the
		# constant's own docstring above for why that precise value matters.
		"fleet_commander": {"name": "Adm. Kestrel", "tactics": BASELINE_TACTICS, "logistics": 50.0, "charisma": 55.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
		"interior_minister": {"name": "Min. Osric Vale", "tactics": 30.0, "logistics": 55.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
		"treasury_minister": {"name": "Min. Dessa Faron", "tactics": 35.0, "logistics": 70.0, "charisma": 40.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
		# Unseated -- officer candidates with no political seat. "genius"
		# (high tactics, low charisma/logistics -- a "low-born genius" per
		# GDD's own framing) and an average officer, so the crony/genius
		# dilemma has real teeth from the default seed alone.
		"genius_officer": {"name": "Cdr. Ilyana Rook", "tactics": 80.0, "logistics": 45.0, "charisma": 30.0, "ambition": 0.0, "alive": true, "seat_id": null},
		"average_officer": {"name": "Cdr. Petra Yun", "tactics": 50.0, "logistics": 50.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": null},
		"junior_officer": {"name": "Cdr. Tomas Reyes", "tactics": 60.0, "logistics": 60.0, "charisma": 45.0, "ambition": 0.0, "alive": true, "seat_id": null},
	}


## Assigns `character_id` as `fleet_id`'s commander -- the private-goods act
## itself (GDD: "every command assignment is a political act"). Returns
## false (no state mutated at all) if the character doesn't exist, isn't
## alive, the fleet isn't `side`'s, or the character ALREADY holds this
## command -- that last guard matters: without it, repeatedly reassigning
## the SAME crony would re-trigger the satisfaction bonus below for free
## (caught by design review), which the clamp alone wouldn't prevent from
## being a free, repeatable action even once already at the ceiling.
static func assign_command(state: StrategicState, side: int, fleet_id: String, character_id: String) -> bool:
	if not state.fleets.has(fleet_id) or state.fleets[fleet_id]["side"] != side:
		return false
	var roster: Dictionary = state.roster[side]
	if not roster.has(character_id) or not roster[character_id]["alive"]:
		return false
	var fleet: Dictionary = state.fleets[fleet_id]
	if fleet.get("commander_id", "") == character_id:
		return false
	fleet["commander_id"] = character_id

	var character: Dictionary = roster[character_id]
	var pol: Dictionary = state.politics[side]
	if character["seat_id"] != null and pol["seats"].has(character["seat_id"]):
		# Seated appointee: buys their OWN seat's satisfaction, charisma-
		# scaled -- clamped, unlike Regime's own pokes (which are all
		# one-sided maxf(0.0, ...) decrements), this is the first-ever
		# unbounded INCREMENT poked in from outside Politics.advance's own
		# self-clamping drift, so it needs its own explicit ceiling clamp.
		var seat: Dictionary = pol["seats"][character["seat_id"]]
		var bonus: float = COMMAND_SATISFACTION_BONUS * character["charisma"] / 50.0
		seat["satisfaction"] = clampf(seat["satisfaction"] + bonus, 0.0, 100.0)
	else:
		# Unseated appointee: "the coalition seethes at the snub" -- every
		# OTHER currently-seated individual seat takes the hit (bloc seats
		# don't personally feel a personnel snub, matching politics.gd's own
		# rigid split).
		for seat in pol["seats"].values():
			if seat["kind"] == "individual":
				seat["satisfaction"] = maxf(0.0, seat["satisfaction"] - SNUB_PENALTY)
	return true


## `fleet`'s currently-assigned commander's tactics stat, or BASELINE_TACTICS
## if unset/missing/dead -- a hand-built fleet dict with no "commander_id"
## key at all (several existing tests construct fleets this way) falls
## through to DEFAULT_COMMANDER_ID, whose seeded tactics IS BASELINE_TACTICS,
## so this is a true no-op for every fleet that's never had assign_command
## called on it.
static func commander_tactics(state: StrategicState, side: int, fleet: Dictionary) -> float:
	var character_id: String = fleet.get("commander_id", DEFAULT_COMMANDER_ID)
	var roster: Dictionary = state.roster.get(side, {})
	if not roster.has(character_id) or not roster[character_id]["alive"]:
		return BASELINE_TACTICS
	return roster[character_id]["tactics"]


static func tactics_uptime_mult(tactics: float) -> float:
	return clampf(1.0 + (tactics - BASELINE_TACTICS) * TACTICS_UPTIME_SCALE, TACTICS_UPTIME_MIN, TACTICS_UPTIME_MAX)


## One battle's worth of ambition/permadeath consequence for a single
## resolved commander id (NOT a fleet_id -- see this file's own call site in
## battle_bridge.gd's apply_result for why: a wiped fleet's dict is already
## erased by the time this fires, so the caller must resolve commander_id
## BEFORE that erase and pass the resolved String here). Safe to call with
## DEFAULT_COMMANDER_ID or any id that resolves to nothing meaningful --
## `.has()`/`alive` guards below make every branch a no-op rather than a
## crash for a fleet that was never actually assigned a real commander.
##
## `bonus_ambition` (issue #29): an optional EXTRA one-time ambition jump on
## top of the normal AMBITION_PER_VICTORY, only ever applied alongside a win
## -- era_events.gd's Act 1 opener uses this for the campaign's first-ever
## contact ("mints your first dangerous hero-admiral"), reusing this
## function's own existence/alive guards rather than a separate ad hoc poke
## in battle_bridge.gd duplicating them.
static func apply_battle_result(state: StrategicState, side: int, commander_id: String, won: bool, wiped: bool, bonus_ambition: float = 0.0) -> void:
	var roster: Dictionary = state.roster.get(side, {})
	if not roster.has(commander_id) or not roster[commander_id]["alive"]:
		return
	var character: Dictionary = roster[commander_id]
	if won:
		character["ambition"] += AMBITION_PER_VICTORY + bonus_ambition
	if wiped:
		character["alive"] = false
		character["seat_id"] = null


## "A brilliant, unsatisfied, ambitious admiral is the classic coup seed"
## (GDD §6), read literally -- consumed by removal.gd's effective_support as
## a small, capped subtraction. A SEATED character counts as a live threat
## only once both their ambition clears the threshold AND their own seat's
## satisfaction is genuinely low; capped in total regardless of how many
## characters qualify, same clamping discipline as coup_insurance_debt/
## loyalty_bonus. Provably 0.0 for the default roster (every character
## starts at ambition=0.0, well under the threshold) -- confirmed against
## every existing test_removal.gd/test_regime.gd scenario, none of which
## touch roster state, so this is a true no-op until a real campaign
## actually grows a character's ambition via a won battle.
static func ambition_threat_penalty(state: StrategicState, side: int) -> float:
	var pol: Dictionary = state.politics[side]
	var roster: Dictionary = state.roster.get(side, {})
	var total := 0.0
	for character in roster.values():
		if character["seat_id"] == null or not character["alive"]:
			continue
		if character["ambition"] <= AMBITION_THREAT_THRESHOLD:
			continue
		var seat: Dictionary = pol["seats"].get(character["seat_id"], {})
		if seat.get("satisfaction", 100.0) < AMBITION_THREAT_SATISFACTION_CEILING:
			total += AMBITION_THREAT_PENALTY
	return minf(total, MAX_AMBITION_THREAT_PENALTY)
