extends SceneTree
## Headless validation for issue #21, Phase 3's go/no-go milestone: "does
## squeezing planets present real dilemmas?" Run:
##   godot --headless --path game --script res://tests/test_home_front_demo.gd
##
## Unlike #17-#20, this issue adds no new mechanics (GDD §12's own Phase 3
## milestone description lists exactly what those four issues already built:
## planet attributes/policies, the grievance->unrest->rebellion pipeline,
## manpower-casualty feedback). This is the validation pass GDD calls for --
## "each phase ends with a playable build and a go/no-go" -- run as extended
## StrategicSim campaigns (mirroring test_strategic_ai.gd's own issue #16
## showable-outcome test, _test_campaign_produces_territory_changes_and_clashes)
## rather than a feature to build. Empirically confirmed via live probes
## before writing these (not assumed): unmanaged extraction across a whole
## territory collapses it to rebellion inside ~30 ticks; the SAME extraction
## level with a real garrison investment not only survives but out-produces
## pure-caution play over a long campaign -- a genuine, skill-rewarding
## dilemma, not "extraction is just bad" or "garrison trivially solves it."

var _failures := 0


func _init() -> void:
	print("test_home_front_demo — Godot ", Engine.get_version_info()["string"])

	_test_unmanaged_extraction_risks_losing_everything()
	_test_managed_extraction_sustains_territory_and_outproduces_caution()
	_test_escalation_always_warns_before_rebelling()

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


const OWNED_SYSTEMS := ["A1", "A2", "A3", "A4"]


func _owned_count(state: StrategicState) -> int:
	var n := 0
	for id in OWNED_SYSTEMS:
		if state.system_owner[id] == 0:
			n += 1
	return n


## The reckless extreme: punitive taxation, total conscription, zero garrison,
## across the player's ENTIRE territory at once, with no course-correction.
## This is deliberately the harshest possible combination -- the dilemma's
## "if you ignore this entirely" failure case.
func _test_unmanaged_extraction_risks_losing_everything() -> void:
	var sim := StrategicSim.new()
	var stream := StrategicCommandStream.new()
	sim.step(stream)
	for id in OWNED_SYSTEMS:
		sim.state.planets[id]["taxation"] = "punitive"
		sim.state.planets[id]["conscription"] = "total"
	for t in range(100):
		sim.step(stream)
	_check(_owned_count(sim.state) < OWNED_SYSTEMS.size(),
		"unmanaged extraction: squeezing every owned planet flat-out, unmanaged, actually costs real territory")


## The skillful middle: real extraction (heavy, not the harshest punitive/
## total extreme) PAIRED with a genuine garrison investment. Confirms the
## dilemma has an answer beyond "never extract" -- managed correctly, it
## should hold every system AND out-produce a purely cautious (default
## moderate/moderate, no garrison) realm over the same horizon, since a
## garrisoned, heavily-taxed planet still earns more materiel per tick than
## an untaxed one once GDD's own taxation revenue_mult table is factored in.
func _test_managed_extraction_sustains_territory_and_outproduces_caution() -> void:
	var managed := StrategicSim.new()
	var managed_stream := StrategicCommandStream.new()
	managed.step(managed_stream)
	for id in OWNED_SYSTEMS:
		managed.state.planets[id]["taxation"] = "heavy"
		managed.state.planets[id]["conscription"] = "heavy"
		managed.state.planets[id]["garrison"] = 40.0

	var cautious := StrategicSim.new()
	var cautious_stream := StrategicCommandStream.new()
	cautious.step(cautious_stream)  # default policy everywhere, never touched

	for t in range(400):
		managed.step(managed_stream)
		cautious.step(cautious_stream)

	_check(_owned_count(managed.state) == OWNED_SYSTEMS.size(),
		"managed extraction: a real garrison investment holds every system even under heavy/heavy policy")
	_check(managed.state.materiel[0] > cautious.state.materiel[0],
		"managed extraction: skillfully squeezed territory out-produces pure caution over a long campaign (got %.0f vs %.0f)" % [
			managed.state.materiel[0], cautious.state.materiel[0]])


## A structural guarantee, not just an empirical observation: Planet.
## UNREST_DRIFT_RATE bounds how far unrest can move in a single tick (at most
## 100 * UNREST_DRIFT_RATE, even from a target of 100 starting at 0), which is
## well under the 30-point gap between any two adjacent escalation thresholds
## (STRIKE_THRESHOLD=60, RIOT_THRESHOLD=75, REBELLION_THRESHOLD=90) -- a planet
## can never skip a warning stage on its way to rebelling, "no gotchas" isn't
## just a design intention, it can't structurally happen otherwise.
func _test_escalation_always_warns_before_rebelling() -> void:
	var max_single_tick_move: float = 100.0 * Planet.UNREST_DRIFT_RATE
	_check(max_single_tick_move < Rebellion.RIOT_THRESHOLD - Rebellion.STRIKE_THRESHOLD,
		"escalation: even the largest possible single-tick unrest jump can't skip past the strikes warning stage")
	_check(max_single_tick_move < Rebellion.REBELLION_THRESHOLD - Rebellion.RIOT_THRESHOLD,
		"escalation: even the largest possible single-tick unrest jump can't skip past the riots warning stage")

	# Confirmed directly too, not just via the bound: drive a planet hard and
	# check every escalation state is actually visited in order on the way to
	# rebellion, not jumped over.
	var state := StrategicState.new()
	state.planets["A1"]["taxation"] = "punitive"
	state.planets["A1"]["conscription"] = "total"
	var seen: Array[String] = []
	for t in range(60):
		Planet.advance(state, "A1")
		var st := Rebellion.escalation_state(state.planets["A1"]["unrest"])
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
		if st == "rebellion":
			break
	_check(seen == ["calm", "strikes", "riots", "rebellion"],
		"escalation: a planet driven to rebellion actually passes through every warning stage in order (got %s)" % [seen])
