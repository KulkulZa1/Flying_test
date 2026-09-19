class_name Scoring
extends RefCounted

var score := 0
var multiplier := 1.0
var high_score := 0

var _path := Config.HIGH_SCORE_PATH
var _since_last_kill := 0.0
var _chaining := false

## The path is injectable so tests never read or clobber a real player's best.
func _init(path := Config.HIGH_SCORE_PATH) -> void:
	_path = path
	high_score = _load_high_score()

## The chain lapses when COMBO_WINDOW passes with no kill.
func advance(dt: float) -> void:
	if not _chaining:
		return
	_since_last_kill += dt
	if _since_last_kill > Config.COMBO_WINDOW:
		_chaining = false
		multiplier = 1.0

func register_kill() -> void:
	if _chaining and _since_last_kill <= Config.COMBO_WINDOW:
		multiplier = minf(multiplier + Config.COMBO_STEP, Config.COMBO_CAP)
	else:
		multiplier = 1.0
	score += int(round(float(Config.BASE_KILL_SCORE) * multiplier))
	_chaining = true
	_since_last_kill = 0.0

## Ends the run's chain as well as its score: a multiplier that outlived a death
## made the first kill of a new life worth triple.
func reset_run() -> void:
	score = 0
	multiplier = 1.0
	_chaining = false
	_since_last_kill = 0.0

func save_high_score() -> void:
	if score <= high_score:
		return
	high_score = score
	var file := ConfigFile.new()
	file.set_value("run", "high_score", high_score)
	file.save(_path)

## A missing file on first launch is normal, not an error.
func _load_high_score() -> int:
	var file := ConfigFile.new()
	if file.load(_path) != OK:
		return 0
	return int(file.get_value("run", "high_score", 0))
