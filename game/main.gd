extends Node2D
## Interactive proving ground for squadron movement & facing (issue #4, GDD §5.1-5.2):
## select squadrons and maneuver them around the plane, paused or at speed. This scene
## never mutates Sim state directly — every order becomes a Command appended to
## `_stream`, timestamped at the sim's current tick, exactly like a recorded replay
## (GDD §11: "no direct UI-to-sim pokes").
##
## Controls:
##   left click / drag   select your squadrons (blue, side 0)
##   right click         move selection to the clicked point (keeps relative spacing)
##   Q / E               turn selection left / right; tap to nudge, hold to keep turning
##   Space               pause / resume
##   1 / 2 / 3           set speed to 1x / 2x / 4x
##
## Facing convention note: Godot 2D is Y-down, so increasing degrees (standard
## atan2/cos/sin math) rotates CLOCKWISE on screen, not counter-clockwise. Q (turn
## left/port) must therefore use a NEGATIVE delta and E (turn right/starboard) a
## POSITIVE one — the opposite of what "increasing angle" naively suggests.

const SEED := 12345
const SELECT_RADIUS := 22.0
const SQUAD_RADIUS := 14.0
const TURN_STEP := 20.0   # single-tap nudge
const HOLD_LEAD := 24.0   # degrees kept "ahead" of current facing per tick while held;
                          # must clear TURN_RATE/TICKS_PER_SEC (one tick's max turn) by a
                          # comfortable margin so the lead never collapses to zero, and
                          # stay far short of 180° so the shortest-path turn never flips.
const PLAYER_SIDE := 0

var _sim: Sim
var _stream: CommandStream
var _label: Label
var _accum := 0.0
var _speed := 1.0
var _paused := false

var _selected: Array[String] = []
var _drag_start = null  # Vector2 or null
var _drag_current := Vector2.ZERO

var _q_held := false
var _e_held := false
var _turn_dir := 0  # -1 = turning left (Q), +1 = turning right (E), 0 = neither held


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat clicks meant for the plane
	add_child(_label)

	_stream = CommandStream.new()
	_spawn_scene()

	_sim = Sim.new(SEED)
	_stream.reset_cursor()
	_update_label()


func _spawn_scene() -> void:
	var player_positions := [
		Vector2(150, 260), Vector2(150, 320), Vector2(150, 380),
		Vector2(90, 290), Vector2(90, 350),
	]
	for i in range(player_positions.size()):
		_stream.record(Commands.make(0, "spawn", {
			"id": "B%d" % (i + 1), "side": 0, "pos": Commands.pos_to_array(player_positions[i]),
			"facing": 0.0, "strength": 4, "flag": i == 0,
		}))
	var enemy_positions := [
		Vector2(950, 260), Vector2(950, 320), Vector2(950, 380), Vector2(1010, 320),
	]
	for i in range(enemy_positions.size()):
		_stream.record(Commands.make(0, "spawn", {
			"id": "R%d" % (i + 1), "side": 1, "pos": Commands.pos_to_array(enemy_positions[i]),
			"facing": 180.0, "strength": 4, "flag": i == 0,
		}))


func _process(delta: float) -> void:
	if not _paused:
		_accum += delta * _speed
		var tick_len := 1.0 / Sim.TICKS_PER_SEC
		while _accum >= tick_len:
			_accum -= tick_len
			if _turn_dir != 0:
				_hold_turn_nudge()
			_sim.step(_stream)
	_update_label()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = mb.position
				_drag_current = mb.position
			else:
				_finish_left_drag(mb.position)
				_drag_start = null
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_issue_group_move(mb.position)
	elif event is InputEventMouseMotion and _drag_start != null:
		_drag_current = (event as InputEventMouseMotion).position
	elif event is InputEventKey:
		var key := (event as InputEventKey).keycode
		if key == KEY_Q or key == KEY_E:
			# Track held state by actual press/release transitions, not the engine's
			# key-repeat "echo" flag (which some platforms/settings never emit at all,
			# and which only ever reports pressed=true — release isn't echoed either
			# way). A held key here just means "still down since the last transition".
			_set_turn_held(key, event.pressed)
		elif event.pressed and not event.echo:
			match key:
				KEY_SPACE:
					_paused = not _paused
				KEY_1:
					_paused = false; _speed = 1.0
				KEY_2:
					_paused = false; _speed = 2.0
				KEY_3:
					_paused = false; _speed = 4.0


func _finish_left_drag(release_pos: Vector2) -> void:
	if _drag_start == null:
		return
	var start: Vector2 = _drag_start
	if start.distance_to(release_pos) < 4.0:
		_select_point(release_pos)
	else:
		_select_box(start, release_pos)


func _select_point(pos: Vector2) -> void:
	var best_id := ""
	var best_dist := SELECT_RADIUS
	for id in _player_squadron_ids():
		var sq: Dictionary = _sim.state.squadrons[id]
		var d: float = (sq["pos"] as Vector2).distance_to(pos)
		if d <= best_dist:
			best_dist = d
			best_id = id
	var picked: Array[String] = []
	if best_id != "":
		picked.append(best_id)
	_selected = picked


func _select_box(a: Vector2, b: Vector2) -> void:
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	var picked: Array[String] = []
	for id in _player_squadron_ids():
		var sq: Dictionary = _sim.state.squadrons[id]
		if rect.has_point(sq["pos"]):
			picked.append(id)
	_selected = picked


func _player_squadron_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _sim.state.squadrons.keys():
		if _sim.state.squadrons[id]["side"] == PLAYER_SIDE:
			out.append(id)
	return out


## Group move: keeps each selected squadron's offset from the group's centroid, so a
## multi-squadron order doesn't collapse everyone onto a single point.
func _issue_group_move(click_pos: Vector2) -> void:
	var live := _selected.filter(func(id): return _sim.state.squadrons.has(id))
	if live.is_empty():
		return
	var centroid := Vector2.ZERO
	for id in live:
		centroid += _sim.state.squadrons[id]["pos"]
	centroid /= live.size()
	for id in live:
		var offset: Vector2 = _sim.state.squadrons[id]["pos"] - centroid
		var target := click_pos + offset
		_stream.record(Commands.make(_sim.state.tick, "order_move", {
			"id": id, "target": Commands.pos_to_array(target),
		}))


## Q/E are tracked as held state, not discrete key events: this is what makes holding
## work at all (a match on "pressed and not echo" only ever fires once per press) and
## makes tap vs. hold naturally exclusive (a tap is just a hold that releases before
## the next sim tick's nudge fires).
func _set_turn_held(key: int, pressed: bool) -> void:
	if key == KEY_Q:
		if _q_held == pressed:
			return
		_q_held = pressed
	else:
		if _e_held == pressed:
			return
		_e_held = pressed

	var new_dir := 0
	if _q_held and not _e_held:
		new_dir = -1
	elif _e_held and not _q_held:
		new_dir = 1
	if new_dir == _turn_dir:
		return
	_turn_dir = new_dir
	if _turn_dir != 0:
		_order_face_all_selected(TURN_STEP * _turn_dir)  # immediate feedback, tap-sized
	else:
		_order_face_all_selected(0.0)  # freeze exactly where it is the instant both release


## Re-anchored to *current* facing (not accumulated onto desired_facing) every tick,
## so the lead is always exactly HOLD_LEAD — bounded, never runs away, never risks
## crossing 180° and flipping the shortest-path turn direction.
func _hold_turn_nudge() -> void:
	_order_face_all_selected(HOLD_LEAD * _turn_dir)


func _order_face_all_selected(offset_deg: float) -> void:
	for id in _selected:
		if not _sim.state.squadrons.has(id):
			continue
		var facing: float = _sim.state.squadrons[id]["facing"]
		_stream.record(Commands.make(_sim.state.tick, "order_face", {
			"id": id, "facing": Geometry.normalize_angle(facing + offset_deg),
		}))


func _update_label() -> void:
	var speed_txt := "paused" if _paused else "%dx" % int(_speed)
	_label.text = ("tick %d   %s   hash %s   selected: %s\n" +
		"drag-select (left) · move (right-click) · turn (Q/E) · speed (Space/1/2/3)") % [
		_sim.state.tick, speed_txt, _sim.state.state_hash().left(10),
		(", ".join(_selected) if not _selected.is_empty() else "none"),
	]


func _draw() -> void:
	if _sim == null:
		return
	for id in _sim.state.squadrons.keys():
		_draw_squadron(id, _sim.state.squadrons[id])
	if _drag_start != null and (_drag_start as Vector2).distance_to(_drag_current) >= 4.0:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(_drag_current)
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.15), true)
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 1.5)


func _draw_squadron(id: String, sq: Dictionary) -> void:
	var pos: Vector2 = sq["pos"]
	var facing_rad := deg_to_rad(sq["facing"])
	var side_color := Color(0.29, 0.62, 1.0) if sq["side"] == PLAYER_SIDE else Color(1.0, 0.35, 0.35)

	# Translucent front-arc wedge (±90°, GDD §5.5's front arc), so facing reads at a glance.
	var wedge := PackedVector2Array([pos])
	var steps := 12
	for i in range(steps + 1):
		var a: float = facing_rad - PI / 2.0 + (PI * i / steps)
		wedge.append(pos + Vector2(cos(a), sin(a)) * SQUAD_RADIUS * 2.6)
	draw_colored_polygon(wedge, Color(side_color.r, side_color.g, side_color.b, 0.10))

	# Selection ring.
	if id in _selected:
		draw_arc(pos, SQUAD_RADIUS + 6.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)

	# Cohesion ring: green at full, red as it drops.
	var cohesion: float = sq["cohesion"]
	var coh_color := Color(1.0, 0.35, 0.25).lerp(Color(0.3, 0.9, 0.4), cohesion / 100.0)
	draw_arc(pos, SQUAD_RADIUS + 3.0, 0.0, TAU * cohesion / 100.0, 20, coh_color, 2.5)

	# Hull: a triangle pointing along facing.
	var nose := pos + Vector2(cos(facing_rad), sin(facing_rad)) * SQUAD_RADIUS
	var back_l := pos + Vector2(cos(facing_rad + 2.5), sin(facing_rad + 2.5)) * SQUAD_RADIUS * 0.8
	var back_r := pos + Vector2(cos(facing_rad - 2.5), sin(facing_rad - 2.5)) * SQUAD_RADIUS * 0.8
	draw_colored_polygon(PackedVector2Array([nose, back_l, back_r]), side_color)
	if sq["flag"]:
		draw_circle(pos, 3.0, Color.WHITE)
