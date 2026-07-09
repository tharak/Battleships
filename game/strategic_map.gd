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
##   Space                      pause / resume
##   1 / 2 / 3                  set speed to 1x / 2x / 4x
##   R                          (once the campaign ends) start a new one

const PLAYER_SIDE := 0
const TICKS_PER_SEC := 2.0  # weeks/real-second at 1x speed
const SYSTEM_RADIUS := 16.0
const FLEET_RADIUS := 8.0
const SELECT_RADIUS := 22.0
const SIDE_COLOR := {
	0: Color(0.29, 0.62, 1.0), 1: Color(1.0, 0.35, 0.35), 2: Color(0.35, 0.8, 0.4), -1: Color(0.55, 0.55, 0.58),
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
		"Space pause/resume · 1/2/3 speed") % [
			_sim.state.tick, speed_txt, fleet_txt,
			int(_sim.state.materiel.get(0, 0.0)), int(_sim.state.materiel.get(1, 0.0)), int(_sim.state.materiel.get(2, 0.0)),
		]
	if _campaign_over:
		_label.text += "\n\n%s\nPress R to start a new campaign" % _campaign_result


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
