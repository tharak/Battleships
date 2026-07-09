extends SceneTree
## Headless determinism test for the GDD §11 architecture rules. Run with:
##   godot --headless --path game --script res://tests/test_determinism.gd
## Exits 0 if every assertion passes, 1 (and prints failures) otherwise.
##
## Regenerate the golden fixture deliberately (never silently) with:
##   godot --headless --path game --script res://tests/test_determinism.gd -- --regen

const SEED := 42
const TICKS := 600
const FIXTURE_PATH := "res://tests/fixtures/replay.json"
const GOLDEN_HASH_PATH := "res://tests/fixtures/replay.hash"

var _failures := 0


func _init() -> void:
	print("test_determinism — Godot ", Engine.get_version_info()["string"])

	if "--regen" in OS.get_cmdline_user_args():
		_regen_golden()
		quit(0)
		return

	_test_repeatability()
	_test_record_replay()
	_test_golden_fixture()
	_test_hash_sensitivity()

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


func _scripted_stream() -> CommandStream:
	var s := CommandStream.new()
	s.record(Commands.make(0, "spawn", {
		"id": "B1", "side": 0, "pos": [2, 5], "facing": 0, "strength": 4, "flag": true,
	}))
	s.record(Commands.make(0, "spawn", {
		"id": "B2", "side": 0, "pos": [2, 7], "facing": 0, "strength": 4, "flag": false,
	}))
	s.record(Commands.make(0, "spawn", {
		"id": "R1", "side": 1, "pos": [18, 5], "facing": 3, "strength": 4, "flag": true,
	}))
	s.record(Commands.make(1, "order_move", {"id": "B1", "target": [10, 5]}))
	s.record(Commands.make(1, "order_move", {"id": "B2", "target": [10, 7]}))
	s.record(Commands.make(1, "order_move", {"id": "R1", "target": [10, 5]}))
	s.record(Commands.make(40, "order_face", {"id": "B2", "facing": 2}))
	s.record(Commands.make(90, "order_move", {"id": "B2", "target": [4, 2]}))
	return s


func _run(seed_value: int, stream: CommandStream, ticks: int) -> String:
	var sim := Sim.new(seed_value)
	sim.run_stream(stream, ticks)
	return sim.state.state_hash()


## 1. Same seed + same stream, two fresh sims -> identical hashes.
func _test_repeatability() -> void:
	var h1 := _run(SEED, _scripted_stream(), TICKS)
	var h2 := _run(SEED, _scripted_stream(), TICKS)
	_check(h1 == h2, "repeatability: identical seed+stream -> identical hash (%s)" % h1.left(12))


## 2. Record commands, save to JSON, reload, replay -> identical hash to a direct run.
func _test_record_replay() -> void:
	var original := _scripted_stream()
	var direct_hash := _run(SEED, original, TICKS)

	var tmp_path := "user://replay_roundtrip_test.json"
	original.save(tmp_path)
	var reloaded := CommandStream.load_stream(tmp_path)
	var replay_hash := _run(SEED, reloaded, TICKS)

	_check(reloaded.commands.size() == original.commands.size(),
		"record->replay: command count preserved (%d)" % reloaded.commands.size())
	_check(direct_hash == replay_hash,
		"record->replay: save/load JSON round trip reproduces the hash")

	var dir := DirAccess.open("user://")
	if dir:
		dir.remove(tmp_path.trim_prefix("user://"))


## 3. Committed golden fixture + expected hash: catches accidental sim-rule drift.
func _test_golden_fixture() -> void:
	if not FileAccess.file_exists(FIXTURE_PATH):
		_check(false, "golden fixture: %s exists (run with -- --regen to create it)" % FIXTURE_PATH)
		return
	var stream := CommandStream.load_stream(FIXTURE_PATH)
	var hash := _run(SEED, stream, TICKS)
	var golden := FileAccess.get_file_as_string(GOLDEN_HASH_PATH).strip_edges()
	_check(hash == golden,
		"golden fixture: replay matches committed hash (got %s, want %s)" %
			[hash.left(12), golden.left(12)])


## 4. Canary: a different seed or an extra command must change the hash. A test suite
## that only ever checks equality can't tell "correct" from "the hash never changes".
func _test_hash_sensitivity() -> void:
	var base := _run(SEED, _scripted_stream(), TICKS)
	var diff_seed := _run(SEED + 1, _scripted_stream(), TICKS)
	_check(base != diff_seed, "sensitivity: different seed -> different hash")

	var extra := _scripted_stream()
	extra.record(Commands.make(5, "order_face", {"id": "R1", "facing": 1}))
	var diff_cmd := _run(SEED, extra, TICKS)
	_check(base != diff_cmd, "sensitivity: one extra command -> different hash")


func _regen_golden() -> void:
	var stream := _scripted_stream()
	stream.save(FIXTURE_PATH)
	var hash := _run(SEED, stream, TICKS)
	var f := FileAccess.open(GOLDEN_HASH_PATH, FileAccess.WRITE)
	f.store_string(hash)
	f.close()
	print("regenerated golden fixture: ", hash)
