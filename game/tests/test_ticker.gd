extends SceneTree
## Headless behavior tests for the event ticker (issue #30, GDD §9). Run:
##   godot --headless --path game --script res://tests/test_ticker.gd
##
## The combined-threshold-bump regression that motivated this issue's own
## design review (a real bug in already-shipped #24/#29 code) is covered in
## tests/test_era_events.gd instead, alongside the constants/functions it
## actually touches (Removal.THRESHOLD_BUMP_CLAMP, EraEvents.
## PRETENDER_THRESHOLD_BUMP) -- not duplicated here.

var _failures := 0


func _init() -> void:
	print("test_ticker — Godot ", Engine.get_version_info()["string"])

	_test_push_truncates_at_max_entries_oldest_first()

	_test_rebellion_advance_emits_stage_changed_on_a_real_transition()
	_test_rebellion_advance_emits_nothing_for_a_same_stage_tick()
	_test_rebellion_advance_skips_stage_changed_for_the_rebellion_transition_itself()

	_test_removal_advance_emits_removal_stage_changed_on_a_real_transition()
	_test_removal_advance_emits_nothing_for_a_same_stage_tick()

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


func _test_push_truncates_at_max_entries_oldest_first() -> void:
	var state := StrategicState.new()
	for i in range(Ticker.MAX_ENTRIES + 2):
		Ticker.push(state, "event %d" % i)
	_check(state.ticker.size() == Ticker.MAX_ENTRIES, "push: caps at MAX_ENTRIES, never grows unbounded")
	_check(state.ticker[0] == "event 2", "push: the OLDEST entries drop off first, not the newest")
	_check(state.ticker[-1] == "event %d" % (Ticker.MAX_ENTRIES + 1), "push: the newest entry is always kept")


## --- Rebellion.advance's new stage_changed event ------------------------------------------

func _test_rebellion_advance_emits_stage_changed_on_a_real_transition() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = Rebellion.STRIKE_THRESHOLD  # calm -> strikes, right at the tie
	var events := Rebellion.advance(state, "A1")
	var found := false
	for e in events:
		if e["type"] == "stage_changed" and e["from"] == "calm" and e["to"] == "strikes":
			found = true
	_check(found, "Rebellion.advance: emits a stage_changed event on a real calm->strikes transition")
	_check(state.planets["A1"]["last_escalation_stage"] == "strikes", "Rebellion.advance: updates its own stored last_escalation_stage")


func _test_rebellion_advance_emits_nothing_for_a_same_stage_tick() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 0.0
	state.planets["A1"]["last_escalation_stage"] = "calm"
	var events := Rebellion.advance(state, "A1")
	for e in events:
		_check(e["type"] != "stage_changed", "Rebellion.advance: no stage_changed event when the stage hasn't actually changed")
	if events.is_empty():
		_check(true, "Rebellion.advance: no events at all for a quiet, unchanged system")


## Rebellion.advance already emits its own dedicated, more detailed
## {"type":"rebellion", "former_side":...} event for this specific
## transition -- a generic stage_changed event too would be a duplicate
## ticker line for the same moment.
func _test_rebellion_advance_skips_stage_changed_for_the_rebellion_transition_itself() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = Rebellion.REBELLION_THRESHOLD
	var events := Rebellion.advance(state, "A1")
	var has_rebellion_event := false
	var has_stage_changed_event := false
	for e in events:
		if e["type"] == "rebellion":
			has_rebellion_event = true
		if e["type"] == "stage_changed":
			has_stage_changed_event = true
	_check(has_rebellion_event, "test setup: the dedicated rebellion event still fires")
	_check(not has_stage_changed_event, "Rebellion.advance: does NOT also emit a generic stage_changed event for the rebellion transition (avoids a duplicate ticker line)")


## --- Removal.advance's new removal_stage_changed event + Array return -------------------

func _test_removal_advance_emits_removal_stage_changed_on_a_real_transition() -> void:
	var state := StrategicState.new()
	for seat in state.politics[0]["seats"].values():
		seat["satisfaction"] = 30.0  # drives support into "plotting" territory
	var events: Array = Removal.advance(state, 0)
	var found := false
	for e in events:
		if e["type"] == "removal_stage_changed" and e["from"] == "stable":
			found = true
	_check(found, "Removal.advance: emits a removal_stage_changed event on a real stable->X transition")
	_check(state.politics[0]["last_removal_stage"] == Removal.escalation_state(Removal.effective_support(state, 0)),
		"Removal.advance: updates its own stored last_removal_stage to match its actual current classification")


func _test_removal_advance_emits_nothing_for_a_same_stage_tick() -> void:
	var state := StrategicState.new()
	# Default seed is "stable"; call advance() once to settle last_removal_stage,
	# then confirm a second call (still stable) emits nothing further.
	Removal.advance(state, 0)
	_check(state.politics[0]["last_removal_stage"] == "stable", "test setup: settled at stable")
	var events: Array = Removal.advance(state, 0)
	for e in events:
		_check(e["type"] != "removal_stage_changed", "Removal.advance: no removal_stage_changed event when the stage hasn't actually changed")
