class_name TestCase
extends RefCounted
## Minimal test base for the headless runner (tests/run_tests.gd).
## Methods whose names start with `test_` are run in declaration order.

var failures: PackedStringArray = []
var _current := ""


func check(condition: bool, message := "condition should be true") -> void:
	if not condition:
		failures.append("%s: %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message := "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s %s" % [_current, str(expected), str(actual), message])


func check_near(actual: float, expected: float, tolerance: float, message := "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %f +- %f, got %f %s" % [_current, expected, tolerance, actual, message])


func run() -> int:
	var count := 0
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			_current = method_name
			call(method_name)
			count += 1
	return count
