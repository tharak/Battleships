extends Node2D
## Interactive proving ground for the battle-layer systems landing in Phase 1
## (GDD §5): movement & facing (#4), beam combat (#5, GDD §5.3/§5.5) — squadrons fire
## automatically at the nearest enemy in range and their own front arc, no manual
## targeting; position is the whole game — formations (#6, GDD §5.4): draw the
## selection up into one of six named shapes — and morale/waver/rout (#7, GDD §5.5):
## sustained losses (worse from the flank/rear) drain morale; a squadron below half
## wavers (gold outline, half fire effectiveness), and at zero it routs (dimmed grey,
## flees the nearest enemy under its own autopilot, cannot fire, ignores orders,
## until it disengages far enough to rally) — and flagship command radius (#8, GDD
## §5.6, drawn as a translucent ring around each flagship): squadrons inside regen
## morale faster and answer orders immediately; outside, orders take ~2s to arrive
## (nothing to click for this — it's just how far a command has to travel). Losing
## the flagship is fleet-wide: every survivor takes an immediate morale shock, and
## regen stays permanently reduced for the rest of the battle. An asteroid field
## (#9, GDD §5.7, drawn as a translucent brownish disc) blocks beam fire passing
## through open space between two squadrons, slows anything moving inside it, and
## hides a squadron standing inside it from anything more than Terrain.
## ASTEROID_DETECT_RADIUS away — the demo spawns one blue squadron already hidden
## inside a field near the enemy line as a working ambush: it opens fire immediately
## with no return shots taken, until an enemy closes the distance and spots it. This
## scene never
## mutates Sim state directly — every order becomes a Command appended to `_stream`,
## timestamped at the sim's current tick (delayed if the squadron is out of command),
## exactly like a recorded replay (GDD §11: "no direct UI-to-sim pokes"). Combat and
## morale need no player order at all; they're a pure consequence of range, arc,
## losses, and command radius, read each tick from live state.
##
## Rendering is 2.5D (GDD §5.1: "rendered in 3D perspective, but gameplay is 2D" —
## the sim plane never stopped being flat; only how it's drawn changed): squadron
## hulls are the real Warship.vox model rendered live on a tilted orthogonal camera,
## while selection/morale/cohesion rings, the front-arc wedge, beams, pips, and the
## command-radius ring stay the same 2D draw calls they always were, just anchored
## at each squadron's screen-projected position. See _setup_3d's docstring for the
## camera/projection details.
##
## Controls:
##   left click / drag   select your squadrons (blue, side 0)
##   right click         move selection to the clicked point (keeps relative spacing)
##   Q / E               turn selection left / right; tap to nudge, hold to keep turning
##   F1-F6               form the selection up: Spindle / Line / Echelon / Crescent /
##                        Sphere / Column (GDD §5.4)
##   Space               pause / resume
##   1 / 2 / 3           set speed to 1x / 2x / 4x
##   scroll wheel / - =  zoom out / in (- and = are the unshifted zoom-out/in keys,
##                       same convention as browsers/map apps)
##   middle-click drag   orbit the camera (horizontal = spin around the battle,
##                       vertical = tilt); the sim plane itself never moves or
##                       rotates, only the view of it does
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
const BEAM_COLOR := {"front": Color(1, 0.85, 0.3, 0.8), "flank": Color(1, 0.55, 0.15, 0.85),
	"rear": Color(1, 0.2, 0.2, 0.9)}
const SLOT_SPACING := 30.0  # plane units between adjacent formation slots
const FORMATION_KEYS := {
	KEY_F1: "spindle", KEY_F2: "line", KEY_F3: "echelon",
	KEY_F4: "crescent", KEY_F5: "sphere", KEY_F6: "column",
}
## 2.5D rendering (the sim plane stays flat, GDD §5.1's "3D perspective, but gameplay
## is 2D" — a Node2D scene can host a Node3D subtree directly: Godot renders the 3D
## content first, then composites this script's own _draw() CanvasItem calls on top
## in the same window, no SubViewport/compositing trick needed). Squadron hulls are
## real MeshInstance3D nodes using the live Warship.vox mesh; everything else
## (selection/morale/cohesion rings, the wavering outline, the front-arc wedge,
## beams, pips, the command-radius ring) stays exactly the 2D drawing it always was,
## just anchored at each squadron's PROJECTED screen position instead of its raw sim
## position, via Camera3D.unproject_position. Those overlays are deliberately a flat
## schematic HUD layer, not physically ground-projected shapes — a fixed pixel radius
## drawn at a projected point, not a "true" perspective ellipse/quad. That's a
## conscious scope line (confirmed with the user), not an oversight.
const WARSHIP_MESH := preload("res://Warship/Package/Warship.vox")
const SIM_TO_WORLD := 0.028      # sim-plane units -> 3D world units
## The imported mesh is already ~7.5 world units long (same physical size as the
## OBJ export: both preserve the source model's real dimensions) — this is an
## ADDITIONAL scale on top of that, not a replacement for it. Sized so a ship reads
## as a small icon relative to the battle plane, roughly matching the old 2D
## SQUAD_RADIUS's proportion to the play area.
const SHIP_MESH_SCALE := 0.32
## Yaw (deg) that makes the mesh's bow point along world +X, matching the sim's
## facing=0 convention (so a squadron's world rotation is just this offset minus its
## sim facing — sign found by trial, same as tools/bake_warship_icon.gd's YAW_DEG,
## since it's the same source mesh's local orientation either way).
const MESH_YAW_OFFSET_DEG := 270.0
## Orthogonal size = how much of the ground plane is visible, so this alone is the
## zoom control (position/tilt don't affect magnification for an orthogonal camera).
## Starting value; the player can zoom live (scroll wheel / - =) between
## CAM_ZOOM_MIN/MAX — see _zoom_by.
const CAM_ORTHO_SIZE := 17.0
const CAM_ZOOM_MIN := 6.0     # close enough to make out hull detail
const CAM_ZOOM_MAX := 40.0    # zoomed out well past the original (pre-zoom-feature) framing
const CAM_ZOOM_KEY_STEP := 2.0     # per - / = press (held keys auto-repeat via the OS)
const CAM_ZOOM_WHEEL_STEP := 1.5   # per wheel notch — finer than a key tap
const CAM_HEIGHT := 15.0   # camera height above the ground plane; pitch comes from look_at, not a fixed angle
const CAM_BACK := 11.0     # camera offset toward the viewer (world +Z) from the framed center
## Camera orbit (middle-mouse drag): the camera sits at a fixed distance from a
## pivot point and always look_at()s it — dragging changes azimuth (spin around
## the pivot) and elevation (how steep the tilt is), never the distance (that's
## what zoom is for) or the pivot itself. Elevation is clamped well short of the
## horizon and of straight-down: this is still meant to read as "3D perspective,
## but gameplay is 2D" (GDD §5.1), not a free-look camera.
const CAM_ELEV_MIN_DEG := 20.0   # close to the horizon, but never quite edge-on
const CAM_ELEV_MAX_DEG := 85.0   # close to straight-down, but never quite top-down
const CAM_ROTATE_SENSITIVITY := 0.25  # degrees of orbit per pixel dragged

var _world3d: Node3D
var _cam3d: Camera3D
var _cam_zoom := CAM_ORTHO_SIZE
var _cam_pivot_world := Vector3.ZERO
var _cam_dist := 0.0
var _cam_azimuth_deg := 0.0
var _cam_elev_deg := 0.0
var _ship_meshes: Dictionary = {}  # squadron id -> MeshInstance3D
var _hull_materials: Array[StandardMaterial3D] = []  # index by side, built once in _setup_3d

var _sim: Sim
var _stream: CommandStream
var _enemy_ai: BattleAI
var _label: Label
var _accum := 0.0
var _speed := 1.0
var _paused := false

var _selected: Array[String] = []
var _drag_start = null  # Vector2 or null (raw screen coords, for the drag-box visual only)
var _drag_current := Vector2.ZERO

var _q_held := false
var _e_held := false
var _turn_dir := 0  # -1 = turning left (Q), +1 = turning right (E), 0 = neither held

var _fire_beams: Array = []  # this frame's [firer_id, target_id, arc] hits, for rendering only


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 15)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat clicks meant for the plane
	add_child(_label)

	_setup_3d()

	_stream = CommandStream.new()
	_spawn_scene()

	_sim = Sim.new(SEED)
	_stream.reset_cursor()
	_enemy_ai = BattleAI.new(1 - PLAYER_SIDE)
	_update_label()


## Fixed frame, no pan/zoom yet (matches the existing 2D game's fixed-canvas
## behavior) — centered roughly on where the demo scene's fleets actually meet.
## Orthogonal, not perspective: a tilted orthogonal camera gives the same "2.5D"
## depth/parallax read (classic oblique/isometric RTS look) without introducing
## distance-dependent scale, which keeps the 2D overlay's fixed-pixel-radius rings
## looking consistent regardless of how far back a squadron is.
func _setup_3d() -> void:
	const CENTER_SIM := Vector2(500, 320)
	var center_world := _sim_to_world(CENTER_SIM)

	_world3d = Node3D.new()
	add_child(_world3d)
	move_child(_world3d, 0)  # 3D renders first; this script's _draw() composites on top regardless

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.8
	env.environment = e
	_world3d.add_child(env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55, -35, 0)
	key_light.light_energy = 1.1
	_world3d.add_child(key_light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(46, 30)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.05, 0.08, 0.14)
	ground.material_override = ground_mat
	ground.position = Vector3(center_world.x, -0.05, center_world.z)
	_world3d.add_child(ground)

	_cam3d = Camera3D.new()
	_cam3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam3d.size = _cam_zoom
	_cam3d.current = true
	_world3d.add_child(_cam3d)

	_cam_pivot_world = center_world
	_cam_dist = Vector2(CAM_HEIGHT, CAM_BACK).length()
	_cam_elev_deg = rad_to_deg(atan2(CAM_HEIGHT, CAM_BACK))
	_cam_azimuth_deg = 0.0
	_update_cam_orbit()

	# Hull tint (one shared material per side, not per-ship): the imported .vox mesh
	# already uses vertex_color_use_as_albedo (confirmed via inspection, not assumed)
	# with a white albedo_color, so setting albedo_color to the side color multiplies
	# it into the model's own voxel-palette shading rather than replacing it — the
	# hull keeps its detail, just cast in the faction's color, matching the same
	# blue/red language every 2D overlay already uses (_side_color).
	for side in [0, 1]:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = _side_color(side)
		_hull_materials.append(mat)


## Zoom is just the orthogonal camera's `size` (smaller = more magnified) — camera
## position/tilt are untouched, so this can't ever change the framing/angle, only
## how much of the ground plane is visible. Screen-space overlays derived from a
## sim-space radius (command radius ring, asteroid field disc) read `_cam_zoom`
## live so they stay correctly sized at any zoom level; SQUAD_RADIUS/SELECT_RADIUS
## deliberately don't (they're a fixed-pixel HUD layer, see the top-of-file note).
func _zoom_by(delta_size: float) -> void:
	_cam_zoom = clampf(_cam_zoom + delta_size, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
	_cam3d.size = _cam_zoom


## Repositions the camera on a sphere of radius _cam_dist around _cam_pivot_world,
## at the current azimuth/elevation, then re-aims it — orbiting never changes
## _cam_pivot_world or _cam_dist, only where on that sphere the camera sits.
func _update_cam_orbit() -> void:
	var az := deg_to_rad(_cam_azimuth_deg)
	var el := deg_to_rad(_cam_elev_deg)
	var offset := Vector3(
		_cam_dist * cos(el) * sin(az),
		_cam_dist * sin(el),
		_cam_dist * cos(el) * cos(az),
	)
	_cam3d.position = _cam_pivot_world + offset
	_cam3d.look_at(_cam_pivot_world, Vector3.UP)


## Middle-mouse drag: horizontal movement orbits azimuth, vertical adjusts
## elevation. `relative` is already a per-event delta, so no separate drag-start
## bookkeeping is needed (unlike the left-click selection box, which needs to draw
## a rectangle from where the drag began).
func _rotate_cam_by(relative: Vector2) -> void:
	_cam_azimuth_deg = fposmod(_cam_azimuth_deg + relative.x * CAM_ROTATE_SENSITIVITY, 360.0)
	_cam_elev_deg = clampf(_cam_elev_deg - relative.y * CAM_ROTATE_SENSITIVITY, CAM_ELEV_MIN_DEG, CAM_ELEV_MAX_DEG)
	_update_cam_orbit()


func _sim_to_world(p: Vector2) -> Vector3:
	return Vector3(p.x * SIM_TO_WORLD, 0.0, p.y * SIM_TO_WORLD)


func _project_to_screen(sim_pos: Vector2) -> Vector2:
	return _cam3d.unproject_position(_sim_to_world(sim_pos))


## The one place a genuinely new world point (not an existing squadron's already-
## known position) needs to come from a screen click: intersect the camera ray with
## the sim's ground plane (world Y=0). Selection stays in screen space instead (see
## _select_point/_select_box) — projecting known points forward is simpler and exact
## regardless of tilt; only "where did the player click on the ground" needs this.
func _screen_to_sim(screen_pos: Vector2) -> Vector2:
	var from := _cam3d.project_ray_origin(screen_pos)
	var dir := _cam3d.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return Vector2(from.x, from.z) / SIM_TO_WORLD
	var t := -from.y / dir.y
	var hit := from + dir * t
	return Vector2(hit.x, hit.z) / SIM_TO_WORLD


## Keeps one MeshInstance3D per live squadron in sync with sim state — spawned on
## first sight, freed the tick a squadron is no longer in state.squadrons (destroyed
## or never existed). Facing maps sim degrees to a world Y-rotation; sign/offset
## found by trial exactly like the bake tool's YAW_DEG (see MESH_YAW_OFFSET_DEG).
func _sync_3d_visuals() -> void:
	var seen := {}
	for id in _sim.state.squadrons.keys():
		seen[id] = true
		var sq: Dictionary = _sim.state.squadrons[id]
		var mi: MeshInstance3D = _ship_meshes.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = WARSHIP_MESH
			mi.scale = Vector3.ONE * SHIP_MESH_SCALE
			mi.material_override = _hull_materials[sq["side"]]
			_world3d.add_child(mi)
			_ship_meshes[id] = mi
		mi.position = _sim_to_world(sq["pos"])
		mi.rotation_degrees.y = MESH_YAW_OFFSET_DEG - sq["facing"]
	for id in _ship_meshes.keys().duplicate():
		if not seen.has(id):
			(_ship_meshes[id] as MeshInstance3D).queue_free()
			_ship_meshes.erase(id)


## The Phase 0 paper prototype's headline matchup (spindle vs. wide line — see
## docs/prototypes/battle-rules.md §10.c) as the default demo: the enemy spawns
## already drawn up in a Wide Line, then reacts under its own AI (issue #10,
## sim/battle_ai.gd) from the very first tick — it isn't scripted to just sit
## there anymore. Press F1 to draw your own squadrons into a Spindle and go pierce
## it; a careless charge should lose to it, a real flank should still beat it.
func _spawn_scene() -> void:
	var player_positions := [
		Vector2(380, 260), Vector2(380, 320), Vector2(380, 380),
		Vector2(320, 290), Vector2(320, 350),
	]
	for i in range(player_positions.size()):
		_stream.record(Commands.make(0, "spawn", {
			"id": "B%d" % (i + 1), "side": 0, "pos": Commands.pos_to_array(player_positions[i]),
			"facing": 0.0, "strength": 15, "flag": i == 0,
		}))

	var enemy_anchor := Vector2(700, 320)
	var enemy_facing := 180.0
	var line := Formations.generate("line", player_positions.size())
	var slots: Array = line["slots"]
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		var pos: Vector2 = enemy_anchor + Vector2(s["fwd"], s["lat"]).rotated(deg_to_rad(enemy_facing)) * SLOT_SPACING
		_stream.record(Commands.make(0, "spawn", {
			"id": "R%d" % (i + 1), "side": 1, "pos": Commands.pos_to_array(pos),
			"facing": enemy_facing, "strength": 15, "flag": i == line["flag"],
		}))

	# Issue #9 (GDD §5.7): an asteroid field south of the enemy line's flank, with a
	# 6th blue squadron already hidden inside it. Its distance to every enemy
	# squadron (~108-190 units) is chosen between Terrain.ASTEROID_DETECT_RADIUS (90)
	# and Combat.RANGE (220): the ambusher can legally fire out (it isn't the one
	# being concealed from itself), but no enemy can see or fire back until
	# something closes to within detection range — this is the issue's showable
	# outcome, "an ambush from an asteroid field that works", playing out
	# automatically with no player input needed.
	var field_pos := Vector2(600, 420)
	_stream.record(Commands.make(0, "spawn_terrain", {
		"id": "asteroid_1", "kind": "asteroid_field",
		"pos": Commands.pos_to_array(field_pos), "radius": 50.0,
	}))
	_stream.record(Commands.make(0, "spawn", {
		"id": "B6", "side": 0, "pos": Commands.pos_to_array(field_pos),
		"facing": 0.0, "strength": 15, "flag": false,
	}))


func _process(delta: float) -> void:
	_fire_beams = []  # only ever show the current frame's beams, never stale ones
	if not _paused:
		_accum += delta * _speed
		var tick_len := 1.0 / Sim.TICKS_PER_SEC
		while _accum >= tick_len:
			_accum -= tick_len
			if _turn_dir != 0:
				_hold_turn_nudge()
			_enemy_ai.act(_sim.state, _stream)
			for ev in _sim.step(_stream):
				if ev["type"] == "hit":
					_fire_beams.append([ev["firer"], ev["target"], ev["arc"]])
	_sync_3d_visuals()
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
			_issue_group_move(_screen_to_sim(mb.position))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(-CAM_ZOOM_WHEEL_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(CAM_ZOOM_WHEEL_STEP)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_start != null:
			_drag_current = mm.position
		if mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_rotate_cam_by(mm.relative)
	elif event is InputEventKey:
		var key := (event as InputEventKey).keycode
		if key == KEY_Q or key == KEY_E:
			# Track held state by actual press/release transitions, not the engine's
			# key-repeat "echo" flag (which some platforms/settings never emit at all,
			# and which only ever reports pressed=true — release isn't echoed either
			# way). A held key here just means "still down since the last transition".
			_set_turn_held(key, event.pressed)
		elif key in FORMATION_KEYS:
			if event.pressed and not event.echo:
				_apply_formation(FORMATION_KEYS[key])
		elif key == KEY_MINUS or key == KEY_EQUAL:
			# Unlike the formation keys, echo is allowed through here — holding the
			# key should keep zooming, the same feel as holding Q/E to keep turning.
			if event.pressed:
				_zoom_by(CAM_ZOOM_KEY_STEP if key == KEY_MINUS else -CAM_ZOOM_KEY_STEP)
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


## Selection compares SCREEN-space positions (projecting each squadron's known sim
## position forward), not sim-space — exact regardless of camera tilt, and avoids
## ever needing the (perspective-distorting) inverse conversion for a selection box.
## Only the right-click "move to this ground point" genuinely needs the inverse
## (_screen_to_sim), since that's the one case with no existing point to project.
func _select_point(screen_pos: Vector2) -> void:
	var best_id := ""
	var best_dist := SELECT_RADIUS
	for id in _player_squadron_ids():
		var sq: Dictionary = _sim.state.squadrons[id]
		var d: float = _project_to_screen(sq["pos"]).distance_to(screen_pos)
		if d <= best_dist:
			best_dist = d
			best_id = id
	var picked: Array[String] = []
	if best_id != "":
		picked.append(best_id)
	_selected = picked


func _select_box(screen_a: Vector2, screen_b: Vector2) -> void:
	var rect := Rect2(screen_a, Vector2.ZERO).expand(screen_b)
	var picked: Array[String] = []
	for id in _player_squadron_ids():
		var sq: Dictionary = _sim.state.squadrons[id]
		if rect.has_point(_project_to_screen(sq["pos"])):
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
		_stream.record(Commands.make(_command_tick(id), "order_move", {
			"id": id, "target": Commands.pos_to_array(target),
		}))


## Flagship command radius (issue #8, GDD §5.6): a squadron outside its own
## flagship's command radius takes "seconds to arrive" — implemented as scheduling
## the recorded command a few ticks in the future instead of at the current tick.
## Needs no Sim-side mechanic: due() already only delivers a command once its
## timestamp arrives, so a delayed timestamp IS the delay.
func _command_tick(squadron_id: String) -> int:
	if not _sim.state.squadrons.has(squadron_id):
		return _sim.state.tick
	var sq: Dictionary = _sim.state.squadrons[squadron_id]
	var flagship: Variant = Command.flagship_pos(sq["side"], _sim.state.squadrons)
	if Command.is_in_command(sq["pos"], flagship):
		return _sim.state.tick
	return _sim.state.tick + Command.ORDER_DELAY_TICKS


## Draw the selection up into a named formation (issue #6, GDD §5.4). This is pure
## order generation on top of the existing order_move+face — see
## sim/formations.gd's docstring for why "reforming takes time and drops cohesion"
## needs no dedicated mechanic: it's just travel time and the existing turn-cohesion
## cost, applied to squadrons headed for a formation slot instead of a bare point.
func _apply_formation(name: String) -> void:
	var live := _selected.filter(func(id): return _sim.state.squadrons.has(id))
	if live.is_empty():
		return
	var anchor := Vector2.ZERO
	var facing_sum := Vector2.ZERO  # circular mean: average unit vectors, not degrees
	for id in live:
		var sq: Dictionary = _sim.state.squadrons[id]
		anchor += sq["pos"]
		facing_sum += Vector2.RIGHT.rotated(deg_to_rad(sq["facing"]))
	anchor /= live.size()
	var facing := rad_to_deg(facing_sum.angle())

	var orders := Formations.assign_orders(_sim.state.squadrons, live, name, anchor, facing, SLOT_SPACING)
	for id in live:
		var o: Dictionary = orders[id]
		_stream.record(Commands.make(_command_tick(id), "order_move", {
			"id": id, "target": Commands.pos_to_array(o["target"]), "face": o["face"],
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
		_stream.record(Commands.make(_command_tick(id), "order_face", {
			"id": id, "facing": Geometry.normalize_angle(facing + offset_deg),
		}))


func _update_label() -> void:
	var speed_txt := "paused" if _paused else "%dx" % int(_speed)
	var blue_n := 0; var blue_str := 0; var blue_routed := 0
	var red_n := 0; var red_str := 0; var red_routed := 0
	for id in _sim.state.squadrons.keys():
		var sq: Dictionary = _sim.state.squadrons[id]
		if sq["side"] == PLAYER_SIDE:
			blue_n += 1; blue_str += sq["strength"]
			if sq["routed"]: blue_routed += 1
		else:
			red_n += 1; red_str += sq["strength"]
			if sq["routed"]: red_routed += 1
	_label.text = ("tick %d   %s   hash %s   selected: %s\n" +
		"Blue: %d squadrons, %d strength, %d routed   Red: %d squadrons, %d strength, %d routed\n" +
		"drag-select (left) · move (right-click) · turn (Q/E) · form up (F1-F6) · speed (Space/1/2/3)") % [
		_sim.state.tick, speed_txt, _sim.state.state_hash().left(10),
		(", ".join(_selected) if not _selected.is_empty() else "none"),
		blue_n, blue_str, blue_routed, red_n, red_str, red_routed,
	]


func _draw() -> void:
	if _sim == null:
		return
	for id in _sim.state.terrain.keys():
		_draw_terrain_field(_sim.state.terrain[id])
	for side in [0, 1]:
		_draw_command_radius(side)
	for beam in _fire_beams:
		_draw_beam(beam[0], beam[1], beam[2])
	for id in _sim.state.squadrons.keys():
		_draw_squadron(id, _sim.state.squadrons[id])
	if _drag_start != null and (_drag_start as Vector2).distance_to(_drag_current) >= 4.0:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(_drag_current)
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.15), true)
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 1.5)


## Asteroid field (issue #9, GDD §5.7): a translucent brownish disc so it reads as
## hazardous/obscuring terrain, distinct from the side-colored command-radius rings.
## Drawn before everything else so it sits as a backdrop, not a foreground mark.
func _draw_terrain_field(field: Dictionary) -> void:
	var center := _project_to_screen(field["pos"])
	var screen_radius: float = field["radius"] * SIM_TO_WORLD * (get_viewport_rect().size.y / _cam_zoom)
	draw_circle(center, screen_radius, Color(0.45, 0.38, 0.32, 0.18))
	draw_arc(center, screen_radius, 0.0, TAU, 40, Color(0.6, 0.52, 0.42, 0.6), 1.5)


## Issue #8's whole point made visible: where you place the flagship IS the shape of
## this circle. Drawn first (under everything else) so it reads as a zone, not a
## mark. A fixed screen-pixel radius at the flagship's projected position — not a
## "true" ground-projected ellipse; see the 2.5D rendering note at the top of this
## file for why that's a deliberate scope line for every overlay in this function
## and the ones below it, not just this one.
func _draw_command_radius(side: int) -> void:
	var flagship: Variant = Command.flagship_pos(side, _sim.state.squadrons)
	if flagship == null:
		return
	var side_color := _side_color(side)
	var screen_radius := Command.COMMAND_RADIUS * SIM_TO_WORLD * (get_viewport_rect().size.y / _cam_zoom)
	draw_arc(_project_to_screen(flagship), screen_radius, 0.0, TAU, 48,
		Color(side_color.r, side_color.g, side_color.b, 0.25), 1.5)


## Arc-colored so a flank/rear hit reads at a glance, not just numerically, but
## blended toward the firer's own side color so it's also clear at a glance whose
## shot this is — a lighter tint than the hull/rings get, so the arc hue (the more
## actionable read: "that was a flank hit") stays dominant.
func _draw_beam(firer_id: String, target_id: String, arc: String) -> void:
	if not _sim.state.squadrons.has(firer_id) or not _sim.state.squadrons.has(target_id):
		return
	var a := _project_to_screen(_sim.state.squadrons[firer_id]["pos"])
	var b := _project_to_screen(_sim.state.squadrons[target_id]["pos"])
	var arc_color: Color = BEAM_COLOR[arc]
	var firer_side: int = _sim.state.squadrons[firer_id]["side"]
	var tinted := arc_color.lerp(_side_color(firer_side), 0.3)
	draw_line(a, b, tinted, 2.0)


## Blue (player) vs. red (enemy) — the one color pair every side-colored overlay
## in this file shares (rings, wedge, beams, hull tint).
func _side_color(side: int) -> Color:
	return Color(0.29, 0.62, 1.0) if side == PLAYER_SIDE else Color(1.0, 0.35, 0.35)


func _draw_squadron(id: String, sq: Dictionary) -> void:
	var pos := _project_to_screen(sq["pos"])
	var facing_rad := deg_to_rad(sq["facing"])
	var routed: bool = sq["routed"]
	var wavering: bool = Morale.is_wavering(sq)
	var base_color := _side_color(sq["side"])
	# Routed = dimmed toward grey, matching the Phase 0 web prototype's convention
	# (docs/prototypes/battle.html: ROUTED fills grey, SHAKEN gets a gold outline).
	var side_color := base_color.lerp(Color(0.23, 0.25, 0.3), 0.6) if routed else base_color

	# Translucent front-arc wedge (±90°, GDD §5.5's front arc), so facing reads at a glance.
	var wedge := PackedVector2Array([pos])
	var steps := 12
	for i in range(steps + 1):
		var a: float = facing_rad - PI / 2.0 + (PI * i / steps)
		wedge.append(pos + Vector2(cos(a), sin(a)) * SQUAD_RADIUS * 2.6)
	draw_colored_polygon(wedge, Color(side_color.r, side_color.g, side_color.b, 0.10))

	# Selection ring.
	if id in _selected:
		draw_arc(pos, SQUAD_RADIUS + 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)

	# Morale ring: green at full, red as it drops — the outer ring, since morale is
	# the more consequential meter (it's what leads to rout).
	var morale: float = sq["morale"]
	var morale_color := Color(1.0, 0.35, 0.25).lerp(Color(0.3, 0.9, 0.4), morale / 100.0)
	draw_arc(pos, SQUAD_RADIUS + 6.0, 0.0, TAU * morale / 100.0, 20, morale_color, 2.5)

	# Cohesion ring: same convention, inner ring.
	var cohesion: float = sq["cohesion"]
	var coh_color := Color(1.0, 0.35, 0.25).lerp(Color(0.3, 0.9, 0.4), cohesion / 100.0)
	draw_arc(pos, SQUAD_RADIUS + 3.0, 0.0, TAU * cohesion / 100.0, 20, coh_color, 2.5)

	# Wavering: a gold outline, same as the web prototype's Shaken state.
	if wavering:
		draw_arc(pos, SQUAD_RADIUS - 1.0, 0.0, TAU, 20, Color(1.0, 0.82, 0.4, 0.9), 2.0)

	# The hull itself is now a real MeshInstance3D (_sync_3d_visuals), not drawn here
	# at all — this function only overlays the schematic 2D HUD on top of it.
	if sq["flag"]:
		draw_circle(pos, 3.0, Color.WHITE)

	# Strength pips, matching the Phase 0 prototypes' convention — losses stay legible.
	var strength: int = sq["strength"]
	for i in range(strength):
		var pip_pos := pos + Vector2(-9 + i * 6, SQUAD_RADIUS + 6)
		draw_circle(pip_pos, 2.0, Color.WHITE)
