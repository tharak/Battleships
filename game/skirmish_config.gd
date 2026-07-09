extends RefCounted
class_name SkirmishConfig
## Carries the player's skirmish menu choices (skirmish_menu.gd) into main.tscn's
## _spawn_scene, as plain `static var`s rather than an autoload singleton Node —
## autoloads are only attached when Godot boots a project normally, NOT when a
## SceneTree subclass is run directly via `--script` (confirmed directly: an
## autoload node is simply absent from get_root() in that mode). Several tests
## (test_command.gd, test_main_scene.gd) instantiate main.tscn's real scene from
## inside a `--script`-run test harness, so anything main.gd depends on at _ready()
## has to work there too — a static var on this class is available everywhere,
## regardless of scene tree state. Defaults match the pre-#11 hardcoded demo scene,
## so running main.tscn directly — every existing test, or the editor — still
## behaves the same as before the menu existed.

const TERRAIN_OPTIONS := {
	"none": "Clear space — no terrain",
	"asteroid_flank": "Asteroid field on the flank (hidden ambush squadron)",
}
const TERRAIN_NAMES := ["none", "asteroid_flank"]

static var player_preset := FleetPresets.DEFAULT
static var enemy_preset := FleetPresets.DEFAULT
static var terrain_option := "asteroid_flank"
