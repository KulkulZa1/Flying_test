extends TestCase

func test_harness_runs_test_methods() -> void:
	check(true, "harness executes methods prefixed test_")
