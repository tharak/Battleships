extends RefCounted
class_name StrategicCommandStream
## Records a command list and serves it back tick-by-tick — mirrors
## sim/command_stream.gd exactly, but validates against StrategicCommands.KINDS
## instead of Commands.KINDS. A separate class rather than a shared/generic one:
## the two layers' command vocabularies are deliberately independent (GDD §5.8's
## "what each layer hands the other" is a defined contract, not shared internals).

var commands: Array[Dictionary] = []
var _next_index := 0


func record(cmd: Dictionary) -> void:
	assert(StrategicCommands.is_valid(cmd), "invalid strategic command: %s" % cmd)
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


static func from_json(text: String) -> StrategicCommandStream:
	var stream := StrategicCommandStream.new()
	var parsed = JSON.parse_string(text)
	assert(parsed is Array, "replay stream must be a JSON array")
	for raw in parsed:
		stream.commands.append(raw as Dictionary)
	return stream
