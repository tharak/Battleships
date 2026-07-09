extends Node2D
## Strategic map demo (issue #12, GDD §4.1/§4.6): the galaxy node-graph, fleets
## moving system-to-system under ticked-pausable time controls, and pickets-based
## fog of war. This scene never mutates StrategicSim state directly — every order
## becomes a StrategicCommand appended to `_stream`, same "no direct UI-to-sim
## pokes" discipline as the battle layer's main.gd (GDD §11).
##
## Scope note: issue #12 is movement + time + fog of war only. Two opposing
## fleets sharing a system don't fight yet (that's issue #14, "battles from map
## contacts") — nothing special happens if they meet here.
##
## Controls:
##   left click a fleet marker   select it (only your own, blue/side 0)
##   left click a system        send the selected fleet there (auto-pathed via
##                               Galaxy.shortest_path over the lane graph)
##   Space                      pause / resume
##   1 / 2 / 3                  set speed to 1x / 2x / 4x

const PLAYER_SIDE := 0
const TICKS_PER_SEC := 2.0  # weeks/real-second at 1x speed
const SYSTEM_RADIUS := 16.0
const FLEET_RADIUS := 8.0
const SELECT_RADIUS := 22.0
const SIDE_COLOR := {0: Color(0.29, 0.62, 1.0), 1: Color(1.0, 0.35, 0.35), -1: Color(0.55, 0.55, 0.58)}

var _sim: StrategicSim
var _stream: StrategicCommandStream
var _label: Label
var _accum := 0.0
var _speed := 1.0
var _paused := false
var _selected_fleet := ""


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_stream = StrategicCommandStream.new()
	_stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Home Fleet", "side": 0, "system": "A1"}))
	_stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "Enemy Fleet", "side": 1, "system": "C1"}))

	_sim = StrategicSim.new()
	_stream.reset_cursor()
	_update_label()


func _process(delta: float) -> void:
	if not _paused:
		_accum += delta * _speed
		var tick_len := 1.0 / TICKS_PER_SEC
		while _accum >= tick_len:
			_accum -= tick_len
			_sim.step(_stream)
	_update_label()
	queue_redraw()


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
	var fleet_txt := "none" if _selected_fleet == "" else _selected_fleet
	_label.text = ("Week %d   %s   selected fleet: %s\n" +
		"left-click a fleet to select it, left-click a system to send it there\n" +
		"Space pause/resume · 1/2/3 speed") % [_sim.state.tick, speed_txt, fleet_txt]


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
		if fid == _selected_fleet:
			draw_arc(pos, FLEET_RADIUS + 6.0, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 2.0)
