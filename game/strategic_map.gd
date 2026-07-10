extends Node2D
## Strategic map demo (issue #12, GDD §4.1/§4.6, extended to a 3-realm war in
## issue #16): the galaxy node-graph, fleets moving system-to-system under
## ticked-pausable time controls, and pickets-based fog of war. This scene
## never mutates StrategicSim state directly — every order becomes a
## StrategicCommand appended to `_stream`, same "no direct UI-to-sim pokes"
## discipline as the battle layer's main.gd (GDD §11).
##
## Three realms (GDD's Phase 2 spec, "player + 2 dumb AI realms"): the player
## (side 0, Sector A) and two independent AI realms (sides 1/2, Sectors B/C —
## strategic/strategic_ai.gd, one instance per realm, called each tick). A
## contact involving the player launches a real tactical battle (issue #14):
## detected via BattleBridge.detect_contact, seeded via BattleBridge.
## seed_skirmish, then a scene change to main.tscn — the live StrategicSim
## survives that round trip via StrategicSession (a static var, since this
## scene's own instance is destroyed by the scene change); returning here
## re-applies the result via BattleBridge.apply_result before resuming. A
## contact NOT involving the player (the two AI realms fighting each other) is
## resolved immediately in place via AutoResolve, with no scene transition at
## all — GDD §5.9's stated purpose for AutoResolve, "resolving AI-vs-AI
## battles between rival successor states."
##
## The campaign ends once only one realm still has a living fleet (no fleet-
## production mechanic exists, so a realm with zero fleets is permanently
## out of the war) or a tick cap is reached (guarantees a demo session
## actually concludes even in a worst-case standoff).
##
## Controls:
##   left click a fleet marker   select it (only your own, blue/side 0)
##   left click a system        send the selected fleet there (auto-pathed via
##                               Galaxy.shortest_path over the lane graph)
##   right click a system       inspect its planet panel (issue #17) -- click again
##                               to deselect; only currently-visible systems can be
##                               inspected (GDD §4.6 fog of war)
##   T / C / [ / ] / O          (while a system you OWN is inspected) cycle
##                               taxation / conscription / garrison -- / garrison
##                               ++ / occupation stance
##   M / P / G                  (issue #22) shift YOUR budget slider toward
##                               military / private / public -- realm-wide,
##                               no system needs to be selected
##   Space                      pause / resume
##   1 / 2 / 3                  set speed to 1x / 2x / 4x
##   R                          (once the campaign ends) start a new one

const PLAYER_SIDE := 0
const TICKS_PER_SEC := 2.0  # weeks/real-second at 1x speed
const SYSTEM_RADIUS := 16.0
const FLEET_RADIUS := 8.0
const SELECT_RADIUS := 22.0
const GARRISON_STEP := 5.0
const SIDE_COLOR := {
	0: Color(0.29, 0.62, 1.0), 1: Color(1.0, 0.35, 0.35), 2: Color(0.35, 0.8, 0.4), -1: Color(0.55, 0.55, 0.58),
	# Issue #18: a rebel-held system (Rebellion.REBEL_SIDE) needs its own entry
	# here -- without one, _draw()'s SIDE_COLOR[owner] lookup below would crash
	# the instant any system actually rebels. A distinct burnt orange so it
	# reads unmistakably differently from any of the three realms.
	Rebellion.REBEL_SIDE: Color(0.85, 0.45, 0.1),
}
const TICK_CAP := 800  # weeks -- guarantees a demo session concludes even in a worst-case standoff

var _sim: StrategicSim
var _stream: StrategicCommandStream
var _ai_realms: Array[StrategicAI] = []
var _label: Label
var _accum := 0.0
var _speed := 1.0
var _paused := false
var _selected_fleet := ""
var _selected_system := ""
var _campaign_over := false
var _campaign_result := ""


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# Not persisted via StrategicSession (unlike _sim) -- recreated fresh each
	# time this scene loads, see strategic_ai.gd's own docstring for why that's
	# a deliberate, harmless choice.
	_ai_realms = [StrategicAI.new(1, "B1"), StrategicAI.new(2, "C1")]

	_stream = StrategicCommandStream.new()

	if StrategicSession.sim == null:
		_sim = StrategicSim.new()
		StrategicSession.sim = _sim
		_stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Home Fleet", "side": 0, "system": "A1", "preset": "line"}))
		_stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Realm B Fleet", "side": 1, "system": "B1", "preset": "line"}))
		_stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Realm C Fleet", "side": 2, "system": "C1", "preset": "line"}))
	else:
		# Resuming a session already in progress -- either just returning from a
		# fought battle (apply its result first) or the player used R to bail
		# back to the map without a contact ever resolving (nothing to apply).
		_sim = StrategicSession.sim
		if SkirmishConfig.from_map_contact:
			var ids := SkirmishConfig.contact_fleet_ids
			BattleBridge.apply_result(_sim.state, ids[0], ids[1],
				SkirmishConfig.battle_side0_strength_left, SkirmishConfig.battle_side1_strength_left,
				SkirmishConfig.contact_system)
			SkirmishConfig.from_map_contact = false

	_stream.reset_cursor()
	_update_label()


func _process(delta: float) -> void:
	# Applying an already-recorded order is NOT the same thing as advancing
	# simulated time -- pausing should only block the latter. Without this,
	# T/C/[/]/O policy changes and fleet move orders issued while paused sit
	# inertly in the stream (step() is what actually applies them, and it's
	# only called below, inside the "not _paused" guard) until the player
	# unpauses, which reads as the controls simply not working. Safe to call
	# every frame regardless of pause state: StrategicCommandStream.due() is a
	# consuming cursor, so this is a harmless no-op once nothing new is due.
	_sim.apply_due_commands(_stream)
	if not _paused and not _campaign_over:
		_accum += delta * _speed
		var tick_len := 1.0 / TICKS_PER_SEC
		while _accum >= tick_len:
			_accum -= tick_len
			for ai in _ai_realms:
				ai.act(_sim.state, _stream)
			_sim.step(_stream)
			var contact := BattleBridge.detect_contact(_sim.state)
			# AI-vs-AI contacts resolve on the spot, no scene transition -- keep
			# resolving chained contacts (possible at 2x/4x speed, where several
			# ticks process per frame) until either none remain or the next one
			# involves the player, who always gets the interactive battle.
			while not contact.is_empty() and not _involves_player(contact):
				_auto_resolve_contact(contact)
				contact = BattleBridge.detect_contact(_sim.state)
			if not contact.is_empty():
				_launch_battle(contact)
				return
			_check_campaign_over()
			if _paused:
				break
	_update_label()
	queue_redraw()


func _involves_player(contact: Array) -> bool:
	return _sim.state.fleets[contact[0]]["side"] == PLAYER_SIDE or _sim.state.fleets[contact[1]]["side"] == PLAYER_SIDE


func _launch_battle(contact: Array) -> void:
	var player_id: String = contact[0] if _sim.state.fleets[contact[0]]["side"] == PLAYER_SIDE else contact[1]
	var enemy_id: String = contact[1] if player_id == contact[0] else contact[0]
	BattleBridge.seed_skirmish(_sim.state, player_id, enemy_id)
	get_tree().change_scene_to_file("res://main.tscn")


func _auto_resolve_contact(contact: Array) -> void:
	var fa: Dictionary = _sim.state.fleets[contact[0]]
	var fb: Dictionary = _sim.state.fleets[contact[1]]
	var system_id: String = fa["system"]
	var result := AutoResolve.resolve(int(fa["strength"]), float(fa["supply"]), int(fb["strength"]), float(fb["supply"]))
	BattleBridge.apply_result(_sim.state, contact[0], contact[1], result["a_left"], result["b_left"], system_id)


## A realm with zero living fleets is permanently out of the war (no fleet-
## production mechanic exists to bring one back) -- the campaign ends once
## only one of {player, realm B, realm C} still has one. TICK_CAP is a fallback
## for a worst-case standoff (a damaged realm turtling at its shipyard
## forever, nobody able to finish it off): whoever leads in territory +
## surviving strength at the cap "wins" for demo purposes.
func _check_campaign_over() -> void:
	if _campaign_over:
		return
	var alive_sides := {}
	for id in _sim.state.fleets.keys():
		alive_sides[_sim.state.fleets[id]["side"]] = true
	if alive_sides.size() <= 1:
		_campaign_over = true
		_paused = true
		_campaign_result = ("VICTORY — every rival realm has been destroyed" if alive_sides.has(PLAYER_SIDE)
			else "DEFEAT — your realm's fleet has been destroyed")
		return
	if _sim.state.tick >= TICK_CAP:
		_campaign_over = true
		_paused = true
		var leader := _score_leader()
		_campaign_result = ("VICTORY (week %d limit reached) — your realm leads in territory and strength" % TICK_CAP
			if leader == PLAYER_SIDE
			else "DEFEAT (week %d limit reached) — a rival realm leads in territory and strength" % TICK_CAP)


## Territory (10 points/system) plus surviving fleet strength, summed per side
## -- the tick-cap tiebreak.
func _score_leader() -> int:
	var scores := {}
	for id in _sim.state.system_owner.keys():
		var side: int = _sim.state.system_owner[id]
		if side >= 0:
			scores[side] = scores.get(side, 0) + 10
	for id in _sim.state.fleets.keys():
		var f: Dictionary = _sim.state.fleets[id]
		scores[f["side"]] = scores.get(f["side"], 0) + int(f["strength"])
	var best_side := -1
	var best_score := -1
	for side in scores.keys():
		if scores[side] > best_score:
			best_score = scores[side]
			best_side = side
	return best_side


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_system_inspect_click(mb.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_paused = not _paused
			KEY_1:
				_paused = false; _speed = 1.0
			KEY_2:
				_paused = false; _speed = 2.0
			KEY_3:
				_paused = false; _speed = 4.0
			KEY_R:
				if _campaign_over:
					StrategicSession.sim = null
					get_tree().reload_current_scene()
			KEY_T:
				_cycle_policy("taxation", Planet.TAXATION_LEVELS)
			KEY_C:
				_cycle_policy("conscription", Planet.CONSCRIPTION_LEVELS)
			KEY_O:
				_cycle_policy("occupation", Planet.OCCUPATION_STANCES)
			KEY_BRACKETLEFT:
				_step_garrison(-GARRISON_STEP)
			KEY_BRACKETRIGHT:
				_step_garrison(GARRISON_STEP)
			KEY_M:
				_shift_budget("budget_military")
			KEY_P:
				_shift_budget("budget_private")
			KEY_G:
				_shift_budget("budget_public")


func _handle_click(pos: Vector2) -> void:
	# Fleets are checked before systems -- a fleet marker sits on top of its
	# system, and selecting the fleet is the more specific action.
	for id in _sim.state.fleets.keys():
		var f: Dictionary = _sim.state.fleets[id]
		if f["side"] != PLAYER_SIDE:
			continue
		if _fleet_pos(f).distance_to(pos) <= SELECT_RADIUS:
			_selected_fleet = id
			return

	if _selected_fleet == "":
		return
	for id in Galaxy.SYSTEMS.keys():
		var sys: Dictionary = Galaxy.SYSTEMS[id]
		if (sys["pos"] as Vector2).distance_to(pos) <= SELECT_RADIUS:
			var fleet: Dictionary = _sim.state.fleets[_selected_fleet]
			var path := Galaxy.shortest_path(fleet["system"], id)
			if not path.is_empty():
				_stream.record(StrategicCommands.make(_sim.state.tick, "order_move", {
					"id": _selected_fleet, "path": path,
				}))
			return


## Issue #17's planet panel: a separate gesture (right-click) from left-click's
## fleet-select/move-order, so it needs zero changes to that existing logic.
## Only a currently-visible system can be inspected (GDD §4.6 fog of war — the
## same Intel.visible_systems gate _draw() already applies to enemy fleets), and
## clicking the already-selected system again deselects it (this scene has no
## other deselect mechanism at all, for fleets or systems).
func _handle_system_inspect_click(pos: Vector2) -> void:
	var visible := Intel.visible_systems(_sim.state, PLAYER_SIDE)
	for id in Galaxy.SYSTEMS.keys():
		var sys: Dictionary = Galaxy.SYSTEMS[id]
		if (sys["pos"] as Vector2).distance_to(pos) <= SELECT_RADIUS and visible.has(id):
			_selected_system = "" if _selected_system == id else id
			return


## T/C/O share this: read the selected system's current level for `field`,
## advance it to the next in `levels` (wrapping), emit a set_policy command.
## A no-op unless a system is selected AND the player actually owns it —
## inspecting a foreign system is read-only.
func _cycle_policy(field: String, levels: Array) -> void:
	if not _can_edit_selected_system():
		return
	var current: String = _pending_policy_value(field)
	var next: String = levels[(levels.find(current) + 1) % levels.size()]
	_stream.record(StrategicCommands.make(_sim.state.tick, "set_policy", {
		"system": _selected_system, "field": field, "value": next,
	}))


func _step_garrison(delta: float) -> void:
	if not _can_edit_selected_system():
		return
	var current: float = _pending_policy_value("garrison")
	_stream.record(StrategicCommands.make(_sim.state.tick, "set_policy", {
		"system": _selected_system, "field": "garrison", "value": maxf(0.0, current + delta),
	}))


## The basis a cycle/step builds on: the selected system's LATEST still-pending
## set_policy value for `field` if one was already recorded this tick (e.g. two
## key presses in a row while paused, before the sim has had a chance to apply
## the first one), or its actual current sim state otherwise. Without this, two
## quick presses of the same key would both read the same stale current value
## and emit the same next value twice, instead of advancing twice.
func _pending_policy_value(field: String) -> Variant:
	for i in range(_stream._next_index, _stream.commands.size()):
		var cmd: Dictionary = _stream.commands[i]
		if cmd["k"] == "set_policy" and cmd["a"]["system"] == _selected_system and cmd["a"]["field"] == field:
			return cmd["a"]["value"]
	return _sim.state.planets[_selected_system][field]


func _can_edit_selected_system() -> bool:
	return _selected_system != "" and _sim.state.system_owner.get(_selected_system, -1) == PLAYER_SIDE


## Issue #22: M/P/G shift the player's own realm-wide budget slider toward
## `field` by BUDGET_STEP, taking proportionally from the other two shares
## (not evenly -- a realm already leaning heavily private keeps that lean
## after a military bump, it doesn't get evenly redistributed away). Emits a
## set_budget command; strategic_sim.gd's _apply renormalizes to sum to 1.0,
## so exact precision here doesn't matter. Always affects the player's own
## realm -- budget is realm-wide, unlike planet policies, so no selected
## system is needed (or checked).
func _shift_budget(field: String) -> void:
	var current := _pending_budget()
	var others: Array[String] = ["budget_military", "budget_private", "budget_public"]
	others.erase(field)
	var new_target: float = current[field] + Politics.BUDGET_STEP
	var remaining: float = maxf(0.0, 1.0 - new_target)
	var others_sum: float = current[others[0]] + current[others[1]]
	var new_a: float
	var new_b: float
	if others_sum > 0.0:
		new_a = current[others[0]] * (remaining / others_sum)
		new_b = current[others[1]] * (remaining / others_sum)
	else:
		new_a = remaining / 2.0
		new_b = remaining / 2.0
	var shares := {field: new_target, others[0]: new_a, others[1]: new_b}
	_stream.record(StrategicCommands.make(_sim.state.tick, "set_budget", {
		"side": PLAYER_SIDE,
		"military": shares["budget_military"], "private": shares["budget_private"], "public": shares["budget_public"],
	}))


## Same "read the latest still-pending command, not just committed sim state"
## fix already applied to planet policies (_pending_policy_value) -- two M/P/G
## presses in a row, before the sim has had a chance to apply the first,
## must build on each other instead of both reading the same stale split.
func _pending_budget() -> Dictionary:
	for i in range(_stream._next_index, _stream.commands.size()):
		var cmd: Dictionary = _stream.commands[i]
		if cmd["k"] == "set_budget" and cmd["a"]["side"] == PLAYER_SIDE:
			var a: Dictionary = cmd["a"]
			return {"budget_military": a["military"], "budget_private": a["private"], "budget_public": a["public"]}
	return _sim.state.politics[PLAYER_SIDE]


func _fleet_pos(f: Dictionary) -> Vector2:
	var from_pos: Vector2 = Galaxy.SYSTEMS[f["system"]]["pos"]
	if f["dest"] == null:
		return from_pos
	var to_pos: Vector2 = Galaxy.SYSTEMS[f["dest"]]["pos"]
	return from_pos.lerp(to_pos, clampf(f["progress"], 0.0, 1.0))


func _update_label() -> void:
	var speed_txt := "paused" if _paused else "%dx" % int(_speed)
	var fleet_txt := "none"
	if _selected_fleet != "" and _sim.state.fleets.has(_selected_fleet):
		var f: Dictionary = _sim.state.fleets[_selected_fleet]
		var max_strength := FleetPresets.total_strength(f.get("preset", FleetPresets.DEFAULT))
		fleet_txt = "%s (supply %d%%, strength %d/%d)" % [_selected_fleet, int(f["supply"]), int(f["strength"]), max_strength]
	_label.text = ("Week %d   %s   selected fleet: %s\n" +
		"Materiel — yours: %d   Realm B: %d   Realm C: %d\n" +
		"left-click a fleet to select it, left-click a system to send it there\n" +
		"right-click a system to inspect it · Space pause/resume · 1/2/3 speed") % [
			_sim.state.tick, speed_txt, fleet_txt,
			int(_sim.state.materiel.get(0, 0.0)), int(_sim.state.materiel.get(1, 0.0)), int(_sim.state.materiel.get(2, 0.0)),
		]
	_label.text += _home_front_warning_text()
	_label.text += _coalition_text()
	_label.text += _planet_panel_text()
	if _campaign_over:
		_label.text += "\n\n%s\nPress R to start a new campaign" % _campaign_result


## Issue #22's "coalition sidebar" (GDD §9): the player's own seats, their
## satisfaction, and the current budget split -- always visible, not gated
## behind selecting anything, since GDD calls the budget slider "the most
## important control... it must never be more than one click away."
func _coalition_text() -> String:
	var pol: Dictionary = _sim.state.politics[PLAYER_SIDE]
	var lines := "\n\n-- Coalition (W=%d) --\n" % pol["seats"].size()
	lines += "budget: military %d%%  private %d%%  public %d%%   (M/P/G to shift)\n" % [
		int(round(pol["budget_military"] * 100.0)), int(round(pol["budget_private"] * 100.0)), int(round(pol["budget_public"] * 100.0)),
	]
	var seat_ids: Array = pol["seats"].keys()
	seat_ids.sort()
	var seat_lines: Array[String] = []
	for id in seat_ids:
		var seat: Dictionary = pol["seats"][id]
		seat_lines.append("%s (%s) %d%%" % [seat["name"], seat["kind"], int(seat["satisfaction"])])
	lines += "  ".join(seat_lines)
	return lines


## Issue #21's showable outcome: "a build where the loudest threat is behind
## your lines" only actually works if a player fixated on a distant war can
## STILL notice it -- the per-system planet panel (below) only shows once you
## already know to right-click that exact world. This is the passive,
## always-visible half: whichever of the player's own systems currently has
## the worst unrest, surfaced unconditionally in the main HUD the instant it
## clears the strikes threshold, not buried behind a click.
func _home_front_warning_text() -> String:
	var worst_id := ""
	var worst_unrest := -1.0
	for id in _sim.state.system_owner.keys():
		if _sim.state.system_owner[id] != PLAYER_SIDE:
			continue
		var unrest: float = _sim.state.planets[id]["unrest"]
		if unrest > worst_unrest:
			worst_unrest = unrest
			worst_id = id
	if worst_id == "" or Rebellion.escalation_state(worst_unrest) == "calm":
		return ""
	return "\n⚠ %s: %s (unrest %d%%)" % [worst_id, Rebellion.escalation_state(worst_unrest).to_upper(), int(worst_unrest)]


## Issue #17's showable outcome: a planet panel where policy changes visibly move
## output and unrest. Issue #18 adds the escalation state (calm/strikes/riots)
## so a squeezed planet "visibly warns" before it flips, plus a distinct
## rebel-held view with siege progress -- there's no policy panel for a system
## in open rebellion, since nobody's governing it in the sense this model
## represents (Rebellion.advance's owner==REBEL_SIDE branch skips Planet.advance
## entirely). Read-only for a system the player doesn't own (no T/C/[/]/O
## effect there, per _can_edit_selected_system) -- still worth inspecting.
func _planet_panel_text() -> String:
	if _selected_system == "" or not _sim.state.planets.has(_selected_system):
		return ""
	var owner: int = _sim.state.system_owner.get(_selected_system, -1)
	if owner == Rebellion.REBEL_SIDE:
		return _rebel_panel_text()
	var p: Dictionary = _sim.state.planets[_selected_system]
	var owned := _can_edit_selected_system()
	var header := "%s (yours)" % _selected_system if owned else "%s (not yours -- read only)" % _selected_system
	var lines := "\n\n-- Planet: %s --\n" % header
	var status := Rebellion.escalation_state(p["unrest"])
	var status_note: String = {
		"calm": "calm", "strikes": "STRIKES -- deliveries at 50%",
		"riots": "RIOTS -- deliveries stopped, garrison under attrition",
	}[status]
	lines += "status: %s\n" % status_note
	lines += "population %d   manpower %d/%d   loyalty %d%%   unrest %d%%\n" % [
		int(p["population"]), int(p["manpower"]), int(Planet.MANPOWER_CAP), int(p["loyalty"]), int(p["unrest"]),
	]
	var delivery := Rebellion.delivery_mult(p)
	lines += "materiel output %.1f/wk   food output %.1f/wk   garrison %d\n" % [
		Planet.materiel_output(p) * delivery, Planet.food_output(p) * delivery, int(p["garrison"]),
	]
	lines += "taxation: %s   conscription: %s   occupation: %s" % [p["taxation"], p["conscription"], p["occupation"]]
	if p["scorched"]:
		lines += "\n(scorched -- retaken by force, still resentful)"
	if owned:
		lines += "\nT taxation · C conscription · [ / ] garrison · O occupation"
	return lines


## A rebel-held system has no policy panel -- just its hostile status and
## whatever siege progress is (or isn't) currently under way against it.
func _rebel_panel_text() -> String:
	var p: Dictionary = _sim.state.planets[_selected_system]
	var lines := "\n\n-- Planet: %s --\nstatus: IN REBELLION -- hostile territory, no supply transit\n" % _selected_system
	if int(p["siege_side"]) >= 0 and p["siege_progress"] > 0.0:
		lines += "siege by side %d: %d/%d ticks" % [int(p["siege_side"]), int(p["siege_progress"]), int(Rebellion.SIEGE_TICKS)]
	else:
		lines += "no siege under way -- a lone fleet parked here starts one"
	# Issue #20: a defection is a slower, free alternative to a siege -- shown
	# even while a siege ISN'T active (the only time it can accumulate at all,
	# per Rebellion._advance_siege), so a ruler watching a mistreated border
	# world can see it coming, not just discover it after the fact.
	if int(p["defection_side"]) >= 0 and p["defection_progress"] > 0.0:
		lines += "\nside %d is winning them over: %d/%d ticks" % [
			int(p["defection_side"]), int(p["defection_progress"]), int(Rebellion.DEFECTION_TICKS),
		]
	return lines


func _draw() -> void:
	if _sim == null:
		return
	var visible := Intel.visible_systems(_sim.state, PLAYER_SIDE)

	for lane in Galaxy.LANES:
		var a: Vector2 = Galaxy.SYSTEMS[lane[0]]["pos"]
		var b: Vector2 = Galaxy.SYSTEMS[lane[1]]["pos"]
		var seen: bool = visible.has(lane[0]) or visible.has(lane[1])
		draw_line(a, b, Color(1, 1, 1, 0.35 if seen else 0.1), 2.0)

	for id in Galaxy.SYSTEMS.keys():
		var sys: Dictionary = Galaxy.SYSTEMS[id]
		var pos: Vector2 = sys["pos"]
		var owner: int = _sim.state.system_owner[id]
		var color: Color = SIDE_COLOR[owner]
		var seen: bool = visible.has(id)
		if not seen:
			color = color.lerp(Color(0.1, 0.1, 0.12), 0.7)
		draw_circle(pos, SYSTEM_RADIUS, color)
		draw_arc(pos, SYSTEM_RADIUS, 0.0, TAU, 24, Color(1, 1, 1, 0.5 if seen else 0.15), 1.5)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-SYSTEM_RADIUS, SYSTEM_RADIUS + 14), id)
		# Shipyard marker (issue #15): a small gold square, only drawn where it
		# actually applies -- a shipyard whose realm no longer owns the system
		# isn't a functioning shipyard for anyone (Shipyard.rebuild checks
		# ownership too, so this stays visually consistent with the mechanic).
		if Shipyard.SHIPYARDS.has(id) and Shipyard.SHIPYARDS[id] == owner:
			var s := SYSTEM_RADIUS * 0.6
			draw_rect(Rect2(pos - Vector2(s, s) / 2.0, Vector2(s, s)), Color(1.0, 0.85, 0.2, 0.9 if seen else 0.25), false, 2.0)
		# Unrest ring (issue #17): green at calm, red as unrest rises, same
		# green-to-red convention as the fleet supply ring below -- "policy
		# changes visibly move ... unrest" is the issue's own showable-outcome
		# wording. Fog of war applies here too: no economic detail for a system
		# the player can't currently see.
		if seen and owner >= 0:
			var unrest: float = _sim.state.planets[id]["unrest"]
			var unrest_color := Color(0.3, 0.9, 0.4).lerp(Color(1.0, 0.35, 0.25), unrest / 100.0)
			draw_arc(pos, SYSTEM_RADIUS + 4.0, 0.0, TAU * unrest / 100.0, 24, unrest_color, 2.5)
		if id == _selected_system:
			draw_arc(pos, SYSTEM_RADIUS + 8.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)

	for fid in _sim.state.fleets.keys():
		var f: Dictionary = _sim.state.fleets[fid]
		# Fog of war: an enemy fleet only renders while it's somewhere the player
		# can currently see (GDD §4.6) -- your own fleets always render.
		if f["side"] != PLAYER_SIDE and not visible.has(f["system"]):
			continue
		var pos := _fleet_pos(f)
		var color: Color = SIDE_COLOR[f["side"]]
		# A fleet holding at a system sits at that system's EXACT position, so a
		# same-colored, smaller circle would be invisible drawn right on top of
		# it -- a lighter fill plus a solid dark outline (unlike the system's own
		# thin, mostly-transparent ring) reads as a distinct token at any zoom.
		draw_circle(pos, FLEET_RADIUS, color.lightened(0.35))
		draw_arc(pos, FLEET_RADIUS, 0.0, TAU, 16, Color(0, 0, 0, 0.9), 2.5)
		# Supply ring (issue #13): green at full, red as it drains, same green-to-
		# red convention as the battle layer's morale ring -- "visibly starves" is
		# the issue's own showable-outcome wording, so this can't just be a number
		# in a tooltip.
		var supply: float = f.get("supply", 100.0)
		var supply_color := Color(1.0, 0.35, 0.25).lerp(Color(0.3, 0.9, 0.4), supply / 100.0)
		draw_arc(pos, FLEET_RADIUS + 4.0, 0.0, TAU * supply / 100.0, 16, supply_color, 2.5)
		if fid == _selected_fleet:
			draw_arc(pos, FLEET_RADIUS + 8.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
