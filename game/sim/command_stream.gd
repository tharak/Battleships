extends RefCounted
class_name CommandStream
## Records a command list and serves it back tick-by-tick. Saves/loads as JSON so a
## recorded stream is a durable fixture (see tests/fixtures/replay.json) — the
## multiplayer-readiness rule from GDD §11 in its simplest possible form: a session is
## nothing but a seed plus this stream.

var commands: Array[Dictionary] = []
var _next_index := 0


func record(cmd: Dictionary) -> void:
	assert(Commands.is_valid(cmd), "invalid command: %s" % cmd)
	commands.append(cmd)


## Commands due at or before `tick` and not yet served, in stream order.
func due(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while _next_index < commands.size() and commands[_next_index]["t"] <= tick:
		out.append(commands[_next_index])
		_next_index += 1
	return out


func reset_cursor() -> void:
	_next_index = 0


func to_json() -> String:
	return JSON.stringify(commands)


static func from_json(text: String) -> CommandStream:
	var stream := CommandStream.new()
	var parsed = JSON.parse_string(text)
	assert(parsed is Array, "replay stream must be a JSON array")
	for raw in parsed:
		stream.commands.append(raw as Dictionary)
	return stream


func save(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(to_json())
	f.close()


## Named load_stream, not `load`, to avoid shadowing Godot's global load().
static func load_stream(path: String) -> CommandStream:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open replay stream: %s" % path)
	var text := f.get_as_text()
	f.close()
	return from_json(text)
