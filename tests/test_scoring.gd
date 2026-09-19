extends TestCase

## A throwaway path so these tests never read or clobber a real player's best.
const TEST_PATH := "user://test_highscore.cfg"

func _fresh() -> Scoring:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	return Scoring.new(TEST_PATH)

func test_a_single_kill_scores_the_base_value() -> void:
	var scoring := _fresh()
	scoring.register_kill()
	check(scoring.score == Config.BASE_KILL_SCORE, "one kill scores the base value")
	check_approx(scoring.multiplier, 1.0, 1e-6, "and leaves the multiplier at one")

func test_quick_kills_chain() -> void:
	var scoring := _fresh()
	scoring.register_kill()
	scoring.advance(Config.COMBO_WINDOW * 0.5)
	scoring.register_kill()
	check(scoring.multiplier > 1.0, "a second kill inside the window raises the multiplier")
	check(scoring.score > Config.BASE_KILL_SCORE * 2,
		"and the second kill is worth more than the first")

func test_slow_kills_do_not_chain() -> void:
	var scoring := _fresh()
	scoring.register_kill()
	scoring.advance(Config.COMBO_WINDOW + 0.1)
	scoring.register_kill()
	check_approx(scoring.multiplier, 1.0, 1e-6, "a kill outside the window breaks the chain")
	check(scoring.score == Config.BASE_KILL_SCORE * 2, "and scores the base value again")

func test_the_multiplier_caps() -> void:
	var scoring := _fresh()
	for i in 40:
		scoring.register_kill()
		scoring.advance(0.1)
	check_approx(scoring.multiplier, Config.COMBO_CAP, 1e-6, "the multiplier caps at COMBO_CAP")

func test_the_chain_expires_without_kills() -> void:
	var scoring := _fresh()
	scoring.register_kill()
	scoring.advance(0.5)
	scoring.register_kill()
	check(scoring.multiplier > 1.0, "the chain is running")
	scoring.advance(Config.COMBO_WINDOW + 0.1)
	check_approx(scoring.multiplier, 1.0, 1e-6, "and lapses once the window passes with no kill")

func test_a_new_best_survives_a_reload() -> void:
	var scoring := _fresh()
	scoring.score = 12345
	scoring.save_high_score()
	var reloaded := Scoring.new(TEST_PATH)
	check(reloaded.high_score == 12345, "a new best is written and read back")

func test_a_worse_run_does_not_overwrite_the_best() -> void:
	var scoring := _fresh()
	scoring.score = 5000
	scoring.save_high_score()
	var second := Scoring.new(TEST_PATH)
	second.score = 10
	second.save_high_score()
	var third := Scoring.new(TEST_PATH)
	check(third.high_score == 5000, "a worse run leaves the stored best alone")

func test_a_missing_file_is_not_an_error() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	var scoring := Scoring.new(TEST_PATH)
	check(scoring.high_score == 0, "first launch starts from zero rather than failing")
