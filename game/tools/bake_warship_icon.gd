extends Node
## One-off tool: renders Warship/Package/Warship.obj (a MagicaVoxel model) from a
## top-down orthographic camera into a static 2D icon, saved to
## res://assets/warship_icon.png. Run with a real rendering context (NOT --headless):
##   godot --path game tools/bake_warship_icon.tscn
##
## The baked icon is what main.gd actually draws (rotated per squadron's facing,
## tinted per side) — this exists only to regenerate that PNG if the model changes;
## it's not part of the running game.

const IMG_SIZE := 512
const MODEL_PATH := "res://Warship/Package/Warship.obj"
const OUT_PATH := "res://assets/warship_icon.png"

# Camera rig rotation, in degrees, applied to the whole rig around Y (yaw) after the
# fixed top-down tilt. 270 was found by trial: the model's bow (bridge tower) ends up
# pointing along +X in the baked image, matching main.gd's facing=0 convention
# exactly, so no compensating rotation offset is needed when drawing it in-game. If
# the source model changes, re-derive this by baking at 0, looking at which way the
# bow points, and rotating until it points right.
const YAW_DEG := 270.0
const CROP_MARGIN := 6  # px of transparent padding kept around the content bounds


func _ready() -> void:
	var mesh: Mesh = load(MODEL_PATH)
	var aabb := mesh.get_aabb()
	print("mesh AABB: ", aabb)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(IMG_SIZE, IMG_SIZE)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	# Center the model on its own bounding-box center so framing is predictable.
	mesh_instance.position = -aabb.get_center()

	# Pivot rotated by YAW_DEG, holding the mesh, so re-orienting the ship is one
	# number to tweak instead of re-deriving camera math.
	var pivot := Node3D.new()
	pivot.rotation_degrees.y = YAW_DEG
	viewport.add_child(pivot)
	pivot.add_child(mesh_instance)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -30, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	var light2 := DirectionalLight3D.new()
	light2.rotation_degrees = Vector3(-60, 150, 0)
	light2.light_energy = 0.5
	viewport.add_child(light2)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	viewport.add_child(env)

	var largest := maxf(aabb.size.x, aabb.size.z)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = largest * 1.15
	cam.position = Vector3(0, aabb.size.y * 3.0 + 5.0, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)  # look straight down (-Y)
	viewport.add_child(cam)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw  # a second frame to be safe after setup

	var img := viewport.get_texture().get_image()

	# Crop the big transparent margin the square camera frame leaves around a long,
	# narrow ship, so the saved texture's aspect ratio matches the ship's own.
	var used := img.get_used_rect()
	var l: int = maxi(0, used.position.x - CROP_MARGIN)
	var t: int = maxi(0, used.position.y - CROP_MARGIN)
	var r: int = mini(img.get_width(), used.position.x + used.size.x + CROP_MARGIN)
	var b: int = mini(img.get_height(), used.position.y + used.size.y + CROP_MARGIN)
	img = img.get_region(Rect2i(l, t, r - l, b - t))

	var dir := "res://assets"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(OUT_PATH)
	print("saved: ", OUT_PATH, " size=", img.get_size())
	get_tree().quit()
