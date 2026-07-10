extends RefCounted
class_name RealmPoliticsAI
## Political AI for one realm (issue #26, GDD §11's risk register: "Realm AI
## can't play politics — an AI ruler that ignores its own coalition
## trivializes the system" — an explicit top-3 project risk). Distinct from
## `strategic/strategic_ai.gd` (fleet movement) — a new, separate concern,
## same "one file per concern" precedent as every prior Phase 4 module
## (regime.gd atop politics.gd/removal.gd, roster.gd atop politics.gd). One
## instance per AI realm (sides 1/2 only, never side 0 — the player's own
## politics stay fully player-controlled), called once per tick from
## strategic_map.gd, right alongside the existing StrategicAI instances.
##
## Everything this file decides over already exists and is fully shipped —
## Politics/Removal/Regime/Roster (#22-#25). This is PURELY a new decision
## layer: no new StrategicState fields, no new commands. Every decision below
## is emitted as a StrategicCommand via the stream (set_budget/
## set_regime_action/assign_command) — this file never pokes `state`
## directly, same "AI is a command-emitting caller, no direct UI-to-sim
## pokes" discipline GDD §11 and strategic_ai.gd's own docstring already
## establish for the player AND the AI alike.
##
## `StrategicAI._my_fleet(state, side)` is called directly here, no refactor
## needed — GDScript doesn't enforce privacy on `_`-prefixed static funcs,
## and tests/test_strategic_ai.gd already calls this exact function
## cross-file, so this is an established, safe convention, not a new one.
##
## Scope, trimmed the same way every Phase 4 issue has been: franchise
## actions (expand/restrict) are CUT from this AI's decision surface — the
## paper prototype's own flagged "sharpest knife on the table," real,
## hard-to-bound downside for uncertain benefit in one pass. AI realms never
## emit them; s_percent only moves for a later issue's AI logic, or the
## player's own realm. "War posture with supply awareness": CONFIRMED, not
## newly built — strategic_ai.gd's own _winnable_target already folds a
## fleet's CURRENT-tick supply into AutoResolve.effective_power before its
## win-margin check, so a starved fleet already reads as weaker right now.
## This is reactive, not predictive (nothing projects supply forward across
## a multi-hop march to a distant target) — a real, deliberately-deferred
## limitation, logged here, not silently dropped.
##
## Live gap this issue makes real (also logged in strategic_ai.gd itself,
## near _winnable_target): once this file starts actually reassigning
## AI-realm commanders based on politics, the military AI's own "is this
## winnable?" judgment stays blind to the (possibly much weaker) commander
## politics just installed, since _winnable_target never reads a fleet's
## real commander tactics at all. Pre-#26 this mismatch was provably inert
## (AI realms never changed commanders); post-#26 it's real. Fixing it means
## threading live commander tactics into the military AI's own decision —
## real scope creep for this issue, deliberately deferred, not missed.
##
## Validated via a 30-campaign, 800-tick headless batch probe (scratchpad,
## not committed — same "probe and tune, don't commit the harness" precedent
## used throughout this project). Important methodological finding:
## `removed_flag` is STICKY (strategic_map.gd's own comment: "the sticky
## (never auto-cleared) removed_flag") — it marks "a coup/election happened
## at least ONCE, ever", not "this realm is currently unhealthy". A realm
## that loses its one fleet (no production exists to rebuild it) predictably
## spirals into repeated removal-crisis cycles over a long campaign
## REGARDLESS of this file's existence (confirmed via an A/B probe: an
## already-militarily-crippled realm shows the SAME eventual removal and
## even HIGHER escalation-state flip counts with NO political AI at all,
## budget frozen at its default split) — per removal.gd's own docstring
## ("your state may outlive you"), this is expected narrative churn for an
## AI realm, not a mechanical failure this issue is scoped to prevent. The
## actual risk GDD's risk register names — an AI ruler that's still
## militarily VIABLE getting needlessly toppled by its own mismanagement —
## measured directly (removed WHILE still holding a living fleet): 0/30
## campaigns, for every side. Any future issue (#27's balance harness, #28's
## Phase 4 demo validation) that re-runs this kind of batch probe should use
## THIS metric ("removed while still militarily viable"), not the naive
## "final removed_flag", which measures something much narrower and can
## look alarming for reasons that have nothing to do with AI quality.

## Design review's own central finding: Politics.advance's own
## SATISFACTION_DRIFT_RATE=0.1 gives a ~9.5-tick time constant (~57%
## converged by tick 8) -- deciding a brand-new FULL-SWING budget target
## before the last one has even settled is the textbook recipe for a limit
## cycle (oscillating "stable->push military" / "plotting->push political"
## forever). Fixed two ways at once: a coarse-enough cadence (~88% converged
## between decisions) AND an INCREMENTAL nudge every cycle (never a full
## replacement) -- either alone would help, both together closes the risk
## from both directions.
const POLITICAL_DECISION_PERIOD_TICKS := 20
const BUDGET_NUDGE_STEP := 0.1

const STABLE_BUDGET_TARGET := {"military": 0.6, "private": 0.2, "public": 0.2}
const CRISIS_INDIVIDUAL_HEAVY_TARGET := {"military": 0.2, "private": 0.6, "public": 0.2}
const CRISIS_BLOC_HEAVY_TARGET := {"military": 0.2, "private": 0.2, "public": 0.6}

const PURGE_SATISFACTION_FLOOR := 20.0
## Regime.purge's own guard rejects at seats.size() <= Regime.PURGE_MIN_W (3)
## -- this AI keeps one extra seat of margin above that hard floor before it
## will even consider a defensive purge, so it's never the purge itself that
## drives a realm down to the structural minimum.
const PURGE_MIN_W_MARGIN := 1

## Regime.broaden's OWN guard allows growth up to W=11->12 (rejects only at
## W>=Regime.BROADEN_MAX_W=12). This AI's own self-imposed cap is deliberately
## lower and MUST be checked as `w < AI_BROADEN_MAX_W`, not `<=` -- the paper
## prototype's own confirmed "dangerous valley" is W in {9,10,11}
## (docs/prototypes/selectorate-game.md), so a cap of exactly 9 would still
## let broaden fire from W=8 (8 < 9), landing AT 9 -- inside the valley on the
## AI's very first opportunistic broaden past the safe zone. 8 is the
## largest cap that can never do that.
const AI_BROADEN_MAX_W := 8
const BROADEN_HEALTH_THRESHOLD := 60.0

var _side: int
var _next_decision_tick := 0


func _init(side: int) -> void:
	_side = side


func act(state: StrategicState, stream: StrategicCommandStream) -> void:
	if state.tick < _next_decision_tick:
		return
	_next_decision_tick = state.tick + POLITICAL_DECISION_PERIOD_TICKS

	var pol: Dictionary = state.politics[_side]
	var threshold_bump: float = Removal.INSTABILITY_THRESHOLD_BUMP if pol.get("instability_ticks_left", 0.0) > 0.0 else 0.0
	var status := Removal.escalation_state(Removal.effective_support(state, _side), threshold_bump)
	var stable: bool = status == "stable"

	_decide_budget(state, stream, pol, stable)
	_decide_patronage(state, stream, pol, stable)
	_decide_regime_action(state, stream, pol, stable)


## Incremental nudge toward whichever target this cycle's status implies --
## never a full-replacement jump (see this file's own docstring for why).
func _decide_budget(state: StrategicState, stream: StrategicCommandStream, pol: Dictionary, stable: bool) -> void:
	var target: Dictionary
	if stable:
		target = STABLE_BUDGET_TARGET
	else:
		var individual_avg := _avg_satisfaction_by_kind(pol, "individual")
		var bloc_avg := _avg_satisfaction_by_kind(pol, "bloc")
		target = CRISIS_INDIVIDUAL_HEAVY_TARGET if individual_avg < bloc_avg else CRISIS_BLOC_HEAVY_TARGET

	var military: float = _nudge(pol["budget_military"], target["military"])
	var private: float = _nudge(pol["budget_private"], target["private"])
	var public: float = _nudge(pol["budget_public"], target["public"])
	stream.record(StrategicCommands.make(state.tick, "set_budget", {
		"side": _side, "military": military, "private": private, "public": public,
	}))


func _nudge(current: float, target: float) -> float:
	return current + clampf(target - current, -BUDGET_NUDGE_STEP, BUDGET_NUDGE_STEP)


## Average satisfaction across every seat of `kind`, or 100.0 ("not a
## concern") if this realm currently has ZERO seats of that kind -- a real,
## confirmed-reachable state (tests/test_regime.gd already builds an all-
## individual, zero-bloc W=3 coalition as an ordinary fixture; repeated
## purges could reach this for real too), not a hypothetical one. Returning a
## HIGH sentinel rather than 0.0/0.0 (a NaN) or a bare 0.0 (which would
## wrongly read a nonexistent kind as "weakest" and permanently bias the
## budget heuristic toward a kind that isn't even present) means a missing
## kind is correctly never the one this heuristic tries to appease -- same
## defensive-floor precedent as Politics._owned_population's own
## divide-by-zero guard, applied here to a different formula.
static func _avg_satisfaction_by_kind(pol: Dictionary, kind: String) -> float:
	var total := 0.0
	var count := 0
	for seat in pol["seats"].values():
		if seat["kind"] == kind:
			total += seat["satisfaction"]
			count += 1
	if count == 0:
		return 100.0
	return total / float(count)


## In crisis: buy loyalty from whoever is closest to becoming a problem (the
## seated, alive, individual character with the LOWEST seat satisfaction).
## Stable: meritocracy -- whichever alive character has the HIGHEST tactics,
## seated or not, since the realm can afford the political cost of a snub
## right now. assign_command's own same-character guard makes emitting this
## every cycle a safe no-op when nothing should actually change.
func _decide_patronage(state: StrategicState, stream: StrategicCommandStream, pol: Dictionary, stable: bool) -> void:
	var fleet_id: String = StrategicAI._my_fleet(state, _side)
	if fleet_id == "":
		return
	var roster: Dictionary = state.roster[_side]
	var best_id := ""
	if stable:
		var best_tactics := -INF
		for id in roster.keys():
			var c: Dictionary = roster[id]
			if c["alive"] and c["tactics"] > best_tactics:
				best_tactics = c["tactics"]
				best_id = id
	else:
		var worst_satisfaction := INF
		for id in roster.keys():
			var c: Dictionary = roster[id]
			if not c["alive"] or c["seat_id"] == null or not pol["seats"].has(c["seat_id"]):
				continue
			var satisfaction: float = pol["seats"][c["seat_id"]]["satisfaction"]
			if satisfaction < worst_satisfaction:
				worst_satisfaction = satisfaction
				best_id = id
		if best_id == "":
			return  # no seated, alive candidate to appease this cycle -- leave the current commander as-is
	stream.record(StrategicCommands.make(state.tick, "assign_command", {
		"side": _side, "fleet_id": fleet_id, "character_id": best_id,
	}))


## At most one regime action per cycle -- Regime's own instability_ticks_left
## cooldown makes rapid-fire moot regardless, but checking here first avoids
## a wasted emission most cycles.
func _decide_regime_action(state: StrategicState, stream: StrategicCommandStream, pol: Dictionary, stable: bool) -> void:
	if pol.get("instability_ticks_left", 0.0) > 0.0:
		return
	var w: int = pol["seats"].size()

	if not stable and w > Regime.PURGE_MIN_W + PURGE_MIN_W_MARGIN:
		var worst := INF
		for seat in pol["seats"].values():
			worst = minf(worst, seat["satisfaction"])
		if worst < PURGE_SATISFACTION_FLOOR:
			stream.record(StrategicCommands.make(state.tick, "set_regime_action", {"side": _side, "action": "purge"}))
			return

	if stable and w < AI_BROADEN_MAX_W:
		var total := 0.0
		for seat in pol["seats"].values():
			total += seat["satisfaction"]
		var avg: float = total / maxf(1.0, float(w))
		if avg > BROADEN_HEALTH_THRESHOLD:
			stream.record(StrategicCommands.make(state.tick, "set_regime_action", {"side": _side, "action": "broaden"}))
