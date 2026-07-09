extends RefCounted
class_name StrategicState
## Plain-data strategic-layer state (GDD §11 architecture, mirrored from the
## battle layer's sim/battle_state.gd — same "plain data, one mutation path"
## discipline, a separate state/sim/command trio because the two layers are
## separate systems that feed each other via defined contracts, GDD §5.8, not
## shared internals).
##
## `tick` is in WEEKS (GDD §2: "1 turn-tick = 1 week"), ticked-pausable per GDD
## Open Question 4's resolution (issue #12: continuous ticked time, not discrete
## turns — matches the battle layer's existing real-time-with-pause UX).
##
## Fleet fields: side (int), system (String, current/last-departed system id),
## dest (String or null — null means holding at `system`, not traveling),
## progress (float 0-1, fraction of the current lane covered), path
## (Array[String], remaining hops queued after `dest` — consumed one at a time
## as each hop completes, see strategic_sim.gd's _start_next_hop).
##
## `system_owner`: id -> side (-1 = neutral/contested), seeded from Galaxy's
## static data and (in a later issue) mutated by battle outcomes/invasions —
## issue #12 itself never changes ownership, just seeds and reads it for intel.

var tick: int = 0  # weeks
var fleets: Dictionary = {}  # id -> Dictionary
var system_owner: Dictionary = {}  # id (String) -> int side


func _init() -> void:
	for id in Galaxy.SYSTEMS.keys():
		system_owner[id] = Galaxy.SYSTEMS[id]["owner"]
