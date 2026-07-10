extends RefCounted
class_name CampaignConfig
## Carries the player's campaign_menu.gd choices into strategic_map.tscn, as
## plain `static var`s rather than an autoload singleton Node -- same reason
## as SkirmishConfig (skirmish_config.gd): autoloads are only attached when
## Godot boots a project normally, NOT when a SceneTree subclass is run
## directly via `--script`, which is exactly how tests/test_strategic_map_
## scene.gd's own `_fresh_map()` helper instantiates strategic_map.tscn.
##
## All three default to "confederacy" (Starts.gd's exact copy of the
## pre-#27 hardcoded defaults) -- so strategic_map.tscn instantiated
## directly, without ever touching this class (every existing test does
## exactly this), sees the current default behavior completely unchanged.

static var player_start_id := "confederacy"
static var ai_b_start_id := "confederacy"
static var ai_c_start_id := "confederacy"
