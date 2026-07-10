extends SceneTree
## Headless validation for issue #28, Phase 4's go/no-go milestone: "do
## autocrat and democrat runs feel different-but-fair, and does the AI
## ruler survive its own politics?" Run:
##   godot --headless --path game --script res://tests/test_phase4_demo.gd
##
## Like issue #21 was for Phase 3 (see test_home_front_demo.gd's own
## docstring), this issue adds no new mechanics -- #22-#27 already built
## everything Phase 4 needed (seats/budget, removal crises, regime actions,
## patronage, realm AI, 6 fixed starts). This is the validation pass GDD
## calls for, run as two extended, scripted StrategicSim campaigns -- one
## "autocrat" (a junta start, governing through military strength and a
## small, loyal inner circle) and one "democrat" (a republic start,
## governing through broad, distributed satisfaction across many bloc
## seats) -- confirming both reach a comparably healthy outcome via
## genuinely different, mechanically real levers, not just different flavor
## text on the same optimal play.
##
## The two "recorded playthroughs" the issue's showable outcome asks for are
## these two scripted campaigns themselves (this project's established
## precedent for a phase-ending demo is a committed, assertion-backed test,
## not a human play session — there's no human player in this pipeline to
## record; the same substitution issue #26/#27 already made for GDD's own
## "headless batches"/"SPI regression" asks).
##
## "Does the AI survive its own politics": sides 1/2 in both campaigns are
## driven ONLY by StrategicAI + RealmPoliticsAI (issue #26), seeded with the
## plain "confederacy" start, giving the scripted player realm a real,
## adversarial galaxy to operate in rather than an empty stage. Reuses the
## non-misleading "removed while still militarily viable" metric #26's own
## validation batch established -- final `removed_flag` is sticky (never
## auto-cleared) and measures something much narrower ("did a coup ever
## happen, at any point"), not "is this realm currently healthy."

var _failures := 0
const CAMPAIGN_TICKS := 500


func _init() -> void:
	print("test_phase4_demo — Godot ", Engine.get_version_info()["string"])

	_test_junta_autocrat_run_survives_via_a_small_loyal_military_core()
	_test_republic_democrat_run_survives_via_broad_distributed_satisfaction()
	_test_both_runs_reach_comparably_healthy_outcomes_via_different_regimes()

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


## Runs one full campaign: side 0 seeded with `player_start_id` and governed
## POLITICALLY by `player_policy` (called every tick, a scripted "player" --
## direct Regime/Roster calls, same precedent test_regime.gd/test_roster.gd
## already use for driving these functions outside the command-stream,
## matching test_home_front_demo.gd's own "directly mutate state for a
## scripted policy" convention). ALL THREE sides get StrategicAI's baseline
## military competence (rebuild/attack/expand/hold) -- this demo compares
## POLITICAL strategy (autocrat vs. democrat), not military skill, so every
## realm needs the same baseline ability to defend itself and not simply sit
## immobile for 500 ticks (a real bug caught empirically: an early draft gave
## side 0 no military AI at all, and its fleet's total passivity crashed its
## own territory/revenue regardless of which political strategy was
## scripted, before a single genuine political comparison could be made).
## Sides 1/2 also get RealmPoliticsAI (issue #26), seeded "confederacy", and
## every contact resolves via AutoResolve (no player-battle scene transition
## exists in this headless harness). Returns the final sim for the caller to
## inspect.
## Returns {"sim": StrategicSim, "removed_while_viable": {side: bool}} --
## the second field uses the SAME non-misleading metric issue #26's own
## validation batch established: final `removed_flag` is STICKY (never
## auto-cleared, strategic_map.gd's own comment says so) and measures "did a
## coup ever happen, at any point in the whole campaign," not "is this realm
## currently healthy" -- an already-militarily-crippled realm predictably
## cycles through repeated removal crises over a long horizon regardless of
## AI quality (confirmed in #26's own A/B probe). The metric that actually
## answers "does the AI survive its own politics" is whether a realm was
## EVER removed WHILE it still held a living fleet.
func _run_scripted_campaign(player_start_id: String, player_policy: Callable) -> Dictionary:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	Starts.apply(sim.state, 0, player_start_id)
	Starts.apply(sim.state, 1, "confederacy")
	Starts.apply(sim.state, 2, "confederacy")
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F0", "side": 0, "system": "A1", "preset": Starts.fleet_preset(player_start_id)}))
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 1, "system": "B1", "preset": "line"}))
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F2", "side": 2, "system": "C1", "preset": "line"}))
	var military_ai := [StrategicAI.new(0, "A1"), StrategicAI.new(1, "B1"), StrategicAI.new(2, "C1")]
	var political_ai := [RealmPoliticsAI.new(1), RealmPoliticsAI.new(2)]
	var removed_while_viable := {0: false, 1: false, 2: false}

	for t in range(CAMPAIGN_TICKS):
		player_policy.call(sim.state)
		for ai in military_ai:
			ai.act(sim.state, stream)
		for pai in political_ai:
			pai.act(sim.state, stream)
		sim.step(stream)

		var contact := BattleBridge.detect_contact(sim.state)
		while not contact.is_empty():
			var fa: Dictionary = sim.state.fleets[contact[0]]
			var fb: Dictionary = sim.state.fleets[contact[1]]
			var tactics_a := Roster.commander_tactics(sim.state, fa["side"], fa)
			var tactics_b := Roster.commander_tactics(sim.state, fb["side"], fb)
			var result := AutoResolve.resolve(int(fa["strength"]), float(fa["supply"]), int(fb["strength"]), float(fb["supply"]), tactics_a, tactics_b)
			BattleBridge.apply_result(sim.state, contact[0], contact[1], result["a_left"], result["b_left"], fa["system"])
			contact = BattleBridge.detect_contact(sim.state)

		for side in [0, 1, 2]:
			var has_fleet := false
			for id in sim.state.fleets.keys():
				if sim.state.fleets[id]["side"] == side:
					has_fleet = true
			if has_fleet and sim.state.politics[side].get("removed_flag", false):
				removed_while_viable[side] = true
	return {"sim": sim, "removed_while_viable": removed_while_viable}


## The autocrat's lever: NEVER broadens (stays at the junta's own starting
## W=3, "governing through a small, loyal inner circle" rather than
## appeasing an ever-growing coalition) and never touches the budget the
## recipe already seeded military-heavy -- surviving on the small-W loyalty
## norm's own bonus (GDD's worked example: high replaceability at low W
## makes every essential "terrified of losing their seat," maximum loyalty)
## rather than broad satisfaction management. Purge is correctly unavailable
## at this exact W (Regime.PURGE_MIN_W=3), which is itself part of the
## point -- the autocrat's tool here is restraint/military strength, not an
## active regime action.
func _test_junta_autocrat_run_survives_via_a_small_loyal_military_core() -> void:
	var result := _run_scripted_campaign("junta", func(_state): pass)
	var sim: StrategicSim = result["sim"]
	var pol: Dictionary = sim.state.politics[0]
	_check(not result["removed_while_viable"][0], "autocrat run: the junta ruler is never removed while still militarily viable, over a %d-tick campaign" % CAMPAIGN_TICKS)
	_check(pol["seats"].size() == 3, "autocrat run: stayed a small, loyal W=3 core the whole campaign -- never broadened")
	_check(is_equal_approx(pol["budget_military"], 0.6), "autocrat run: kept the junta's own military-heavy budget throughout, no political micromanagement")
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 0)) in ["stable", "plotting"],
		"autocrat run: ends the campaign in a recoverable state, not an active crisis")


## The democrat's lever: broadens further whenever comfortably stable
## (growing an ALREADY-large coalition even larger -- "more inclusive," the
## opposite direction from the autocrat's restraint) and reassigns command
## to a SEATED candidate whenever any individual seat looks weak (buying
## broad loyalty across many named seats, not leaning on a loyalty-norm
## bonus a large W structurally denies it -- Removal's own worked example:
## low S/W makes essentials BOLD, low loyalty). Never purges -- a democrat
## doesn't prune its own coalition.
func _test_republic_democrat_run_survives_via_broad_distributed_satisfaction() -> void:
	var policy := func(state: StrategicState):
		var pol: Dictionary = state.politics[0]
		if pol.get("instability_ticks_left", 0.0) <= 0.0:
			var support := Removal.effective_support(state, 0)
			if Removal.escalation_state(support) == "stable" and pol["seats"].size() < 12:
				Regime.broaden(state, 0)
		var roster: Dictionary = state.roster[0]
		var worst_id := ""
		var worst_satisfaction := INF
		for id in roster.keys():
			var c: Dictionary = roster[id]
			if c["alive"] and c["seat_id"] != null and pol["seats"].has(c["seat_id"]):
				var s: float = pol["seats"][c["seat_id"]]["satisfaction"]
				if s < worst_satisfaction:
					worst_satisfaction = s
					worst_id = id
		if worst_id != "":
			for fid in state.fleets.keys():
				if state.fleets[fid]["side"] == 0:
					Roster.assign_command(state, 0, fid, worst_id)

	var result := _run_scripted_campaign("republic", policy)
	var sim: StrategicSim = result["sim"]
	var pol: Dictionary = sim.state.politics[0]
	_check(not result["removed_while_viable"][0], "democrat run: the republic ruler is never removed while still militarily viable, over a %d-tick campaign" % CAMPAIGN_TICKS)
	_check(pol["seats"].size() >= 10, "democrat run: stayed at or grew past the republic's own starting W=10 -- never shrank")
	_check(pol["budget_military"] < 0.4, "democrat run: military spending stayed well below an autocrat's level -- the broad-satisfaction lever, not force")
	_check(Removal.escalation_state(Removal.effective_support(sim.state, 0)) in ["stable", "plotting"],
		"democrat run: ends the campaign in a recoverable state, not an active crisis")


## The issue's own central question, checked directly: two structurally
## OPPOSITE strategies (small vs. large W, military vs. patronage levers,
## restraint vs. active regime-growth) both reach a comparable outcome --
## and, per GDD's own risk register, the AI-controlled realms in BOTH
## campaigns also survive their own politics without ever needing player
## input at all.
func _test_both_runs_reach_comparably_healthy_outcomes_via_different_regimes() -> void:
	var junta_result := _run_scripted_campaign("junta", func(_state): pass)
	var republic_policy := func(state: StrategicState):
		var pol: Dictionary = state.politics[0]
		if pol.get("instability_ticks_left", 0.0) <= 0.0 and Removal.escalation_state(Removal.effective_support(state, 0)) == "stable" and pol["seats"].size() < 12:
			Regime.broaden(state, 0)
	var republic_result := _run_scripted_campaign("republic", republic_policy)
	var junta_sim: StrategicSim = junta_result["sim"]
	var republic_sim: StrategicSim = republic_result["sim"]

	var junta_support := Removal.effective_support(junta_sim.state, 0)
	var republic_support := Removal.effective_support(republic_sim.state, 0)
	_check(absf(junta_support - republic_support) < 40.0,
		"different but fair: autocrat (support %.1f) and democrat (support %.1f) end up in a comparable ballpark, not one dominating the other" % [junta_support, republic_support])
	_check(junta_sim.state.politics[0]["seats"].size() != republic_sim.state.politics[0]["seats"].size(),
		"different but fair: the two runs really did end up structurally different regime shapes (W=%d vs W=%d)" % [
			junta_sim.state.politics[0]["seats"].size(), republic_sim.state.politics[0]["seats"].size()])

	# "Does the AI survive its own politics" -- both AI-controlled realms, in
	# BOTH campaigns, checked directly (not re-derived from #26/#27's own
	# separate probes -- this phase's own demo should stand on its own), using
	# the same non-misleading "removed while still militarily viable" metric.
	for result in [junta_result, republic_result]:
		for side in [1, 2]:
			_check(not result["removed_while_viable"][side],
				"AI survives its own politics: side %d was never removed while still militarily viable" % side)
