extends Node2D
## Deliberately dumb scene proving the sim/render boundary (GDD §11): a Sim instance
## fed a scripted CommandStream, stepped on a fixed timer, with its live state shown
## in a Label. No rendering, no input, no gameplay — real battle rendering is #4+.
## This scene must never mutate state directly; every change flows through commands
## recorded on `_stream` before the sim starts.

const SEED := 12345

var _sim: Sim
var _stream: CommandStream
var _label: Label
var _accum := 0.0


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)

	_stream = CommandStream.new()
	_stream.record(Commands.make(0, "spawn", {
		"id": "B1", "side": 0, "pos": [2, 5], "facing": 0, "strength": 4, "flag": true,
	}))
	_stream.record(Commands.make(0, "spawn", {
		"id": "R1", "side": 1, "pos": [18, 5], "facing": 3, "strength": 4, "flag": true,
	}))
	_stream.record(Commands.make(1, "order_move", {"id": "B1", "target": [10, 5]}))
	_stream.record(Commands.make(1, "order_move", {"id": "R1", "target": [10, 5]}))

	_sim = Sim.new(SEED)
	_stream.reset_cursor()
	_update_label()


func _process(delta: float) -> void:
	_accum += delta
	var tick_len := 1.0 / Sim.TICKS_PER_SEC
	while _accum >= tick_len:
		_accum -= tick_len
		_sim.step(_stream)
		_update_label()


func _update_label() -> void:
	var lines := ["tick %d   hash %s" % [_sim.state.tick, _sim.state.state_hash().left(12)]]
	var ids := _sim.state.squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = _sim.state.squadrons[id]
		lines.append("  %s  side=%d pos=%s facing=%d str=%d" %
			[id, sq["side"], sq["pos"], sq["facing"], sq["strength"]])
	_label.text = "\n".join(lines)
