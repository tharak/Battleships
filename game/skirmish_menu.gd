extends Control
## Skirmish menu (issue #11): pick fleet presets for both sides and a terrain
## option, then start a battle in main.tscn. Writes the choices into the
## SkirmishConfig autoload (skirmish_config.gd) — main.gd's _spawn_scene reads
## them from there. This is the Phase 1 go/no-go build's entry point
## (project.godot's main scene): "a build anyone can download and play a battle
## in" starts here, not straight into main.tscn.

var _player_option: OptionButton
var _enemy_option: OptionButton
var _terrain_option: OptionButton


func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(40, 40)
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)

	var title := Label.new()
	title.text = "Successor Stars — Skirmish"
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pick your fleet, the enemy's fleet, and the battlefield. Then fight."
	panel.add_child(subtitle)

	_player_option = _add_picker(panel, "Your fleet:", FleetPresets.NAMES,
		func(n): return String(FleetPresets.PRESETS[n]["label"]))
	_enemy_option = _add_picker(panel, "Enemy fleet:", FleetPresets.NAMES,
		func(n): return String(FleetPresets.PRESETS[n]["label"]))
	_terrain_option = _add_picker(panel, "Terrain:", SkirmishConfig.TERRAIN_NAMES,
		func(n): return String(SkirmishConfig.TERRAIN_OPTIONS[n]))

	_select_default(_player_option, FleetPresets.NAMES, SkirmishConfig.player_preset)
	_select_default(_enemy_option, FleetPresets.NAMES, SkirmishConfig.enemy_preset)
	_select_default(_terrain_option, SkirmishConfig.TERRAIN_NAMES, SkirmishConfig.terrain_option)

	var start := Button.new()
	start.text = "Start Battle"
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_on_start_pressed)
	panel.add_child(start)

	var hint := Label.new()
	hint.text = ("Once in battle: drag-select (left click), right-click to move, " +
		"Q/E to turn, F1-F6 to form up, scroll/-/= to zoom, middle-drag to orbit " +
		"the camera, R to come back here.")
	hint.custom_minimum_size = Vector2(560, 0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(hint)


func _add_picker(parent: Node, label_text: String, names: Array, label_fn: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var opt := OptionButton.new()
	for n in names:
		opt.add_item(label_fn.call(n))
	row.add_child(opt)
	return opt


func _select_default(opt: OptionButton, names: Array, current: String) -> void:
	opt.select(maxi(names.find(current), 0))


func _on_start_pressed() -> void:
	SkirmishConfig.player_preset = FleetPresets.NAMES[_player_option.selected]
	SkirmishConfig.enemy_preset = FleetPresets.NAMES[_enemy_option.selected]
	SkirmishConfig.terrain_option = SkirmishConfig.TERRAIN_NAMES[_terrain_option.selected]
	get_tree().change_scene_to_file("res://main.tscn")
