extends Control
## Campaign start menu (issue #27): pick your own hand-balanced fixed start
## from Starts.gd's 6 recipes, then begin a campaign in strategic_map.tscn.
## Same VBoxContainer/OptionButton/"Start" button structure skirmish_menu.gd
## already established for an analogous choice (issue #11). Writes into
## CampaignConfig (campaign_config.gd) -- strategic_map.gd's own _ready()
## reads it from there, same handoff shape as SkirmishConfig/main.gd.
##
## Not wired into project.godot's main scene (that stays skirmish_menu.tscn,
## the Phase 1 battle-only entry point) -- launched directly, same as
## strategic_map.tscn itself already is for demoing the campaign layer.

var _player_option: OptionButton


func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(40, 40)
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)

	var title := Label.new()
	title.text = "Successor Stars — Campaign"
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pick your realm's starting shape. The other two realms each draw a different one at random."
	panel.add_child(subtitle)

	_player_option = _add_picker(panel, "Your start:", Starts.IDS, func(id): return Starts.label(id))
	_select_default(_player_option, Starts.IDS, CampaignConfig.player_start_id)

	var start := Button.new()
	start.text = "Start Campaign"
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_on_start_pressed)
	panel.add_child(start)

	var hint := Label.new()
	hint.text = ("Once in the campaign: click a fleet then a system to move it, right-click a system to " +
		"inspect it, T/C/[/]/O policy, M/P/G budget, X/B/F/N regime actions, K to cycle your fleet's " +
		"commander, Space to pause, R once it ends to start a new one.")
	hint.custom_minimum_size = Vector2(560, 0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(hint)


func _add_picker(parent: Node, label_text: String, ids: Array, label_fn: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var opt := OptionButton.new()
	for id in ids:
		opt.add_item(String(label_fn.call(id)))
	row.add_child(opt)
	return opt


func _select_default(opt: OptionButton, ids: Array, current: String) -> void:
	opt.select(maxi(ids.find(current), 0))


## The two AI realms each get a DIFFERENT other start, drawn at random from
## whichever 5 remain once the player's own choice is excluded -- not the
## same one twice, so a campaign always shows at least 3 distinct shapes
## side by side (never the player's own start duplicated onto a rival).
func _on_start_pressed() -> void:
	CampaignConfig.player_start_id = Starts.IDS[_player_option.selected]
	var remaining: Array = Starts.IDS.duplicate()
	remaining.erase(CampaignConfig.player_start_id)
	remaining.shuffle()
	CampaignConfig.ai_b_start_id = remaining[0]
	CampaignConfig.ai_c_start_id = remaining[1]
	StrategicSession.sim = null  # a fresh campaign, not resuming any prior session
	get_tree().change_scene_to_file("res://strategic_map.tscn")
