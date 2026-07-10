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

## A map-contact battle's fleets are usually damaged/rebuilt from their preset's
## original total (strategic/shipyard.gd) by the time they fight — -1 means "use
## the preset's own total", so the skirmish menu and every existing test (which
## never touch these) still spawn a fresh, full-strength preset exactly as
## before this override existed. Set by battle_bridge.gd's seed_skirmish to the
## contacting fleets' actual current strategic strength; main.gd's _spawn_scene
## distributes it across the preset's squadron count instead of using the
## preset's flat per-squadron strength, so a mauled fleet actually shows up
## mauled in the tactical view, not full-strength every time.
static var player_total_strength := -1
static var enemy_total_strength := -1

## Issue #14, GDD §5.8: supply-driven tactical modifiers, set by strategic/
## battle_bridge.gd when a map contact launches a battle. Default 1.0/100.0
## (no penalty) so the skirmish menu and every existing test — which never
## touch these — behave exactly as before #14.
static var player_uptime_mult := 1.0
static var player_morale_cap := 100.0
static var enemy_uptime_mult := 1.0
static var enemy_morale_cap := 100.0

## True only when this battle was launched from a map contact (strategic_map.gd),
## not the skirmish menu — main.gd's battle-over handling uses this to decide
## whether to write results back via battle_bridge.gd and return to
## strategic_map.tscn instead of skirmish_menu.tscn. contact_fleet_ids is
## [player_fleet_id, enemy_fleet_id] from the contact that triggered this
## battle. contact_system (issue #16) is the system they were both standing in
## when the contact fired — threaded through explicitly rather than
## reconstructed after the battle, since a mutual wipeout erases BOTH fleets'
## dicts, leaving nothing to read a "system" field off of afterward.
static var from_map_contact := false
static var contact_fleet_ids: Array[String] = []
static var contact_system := ""

## Battle -> strategic write-back (main.gd fills these in on battle-over when
## from_map_contact is true; strategic_map.gd reads and applies them via
## BattleBridge.apply_result on the next _ready(), then clears from_map_contact).
static var battle_side0_strength_left := 0
static var battle_side1_strength_left := 0
