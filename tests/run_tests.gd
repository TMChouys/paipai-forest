extends SceneTree
## 無頭測試：godot --headless --path . --script res://tests/run_tests.gd

var passed := 0
var failed := 0


func _init() -> void:
	_test_interp()
	if ResourceLoader.exists("res://tests/test_tasks.gd"):
		var extra = load("res://tests/test_tasks.gd").new()
		extra.run(self)
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", name, "  ", detail)


func out_lines(r: Dictionary) -> Array:
	var a: Array = []
	for o in r.outputs:
		a.append(o.text)
	return a


func _test_interp() -> void:
	var r := PyInterp.run("print(\"走到椅子\")\nprint(\"搬起\")\n")
	check("basic print", r.ok and out_lines(r) == ["走到椅子", "搬起"], str(r))

	r = PyInterp.run("a = 4\nprint(f\"向前推{a}格\")\n")
	check("fstring", r.ok and out_lines(r) == ["向前推4格"], str(r))

	r = PyInterp.run("print（\"hi\"）")
	check("fullwidth paren", not r.ok and r.error.kind == "全形符號" and r.error.line == 1, str(r.error))

	r = PyInterp.run("print(“hi”)")
	check("fullwidth quote", not r.ok and r.error.kind == "全形符號", str(r.error))

	r = PyInterp.run("prnt(\"hi\")")
	check("name typo hint", not r.ok and r.error.hint.contains("print"), str(r.error))

	r = PyInterp.run("print(向前走)")
	check("unquoted chinese", not r.ok and r.error.hint.contains("引號"), str(r.error))

	r = PyInterp.run("rain = True\nif rain:\n    print(\"A\")\nelse:\n    print(\"B\")\n")
	check("if true", r.ok and out_lines(r) == ["A"], str(r))

	r = PyInterp.run("rain = False\nif rain:\n    print(\"A\")\nelse:\n    print(\"B\")\n")
	check("if false", r.ok and out_lines(r) == ["B"], str(r))

	r = PyInterp.run("w = 5\nif w > 5:\n    print(\"推\")\nelif w == 5:\n    print(\"剛好\")\nelse:\n    print(\"搬\")\n")
	check("elif", r.ok and out_lines(r) == ["剛好"], str(r))

	r = PyInterp.run("if rain\n    print(1)\n")
	check("missing colon", not r.ok and r.error.message.contains("冒號"), str(r.error))

	r = PyInterp.run("rain = 1\nif rain = 1:\n    print(1)\n")
	check("= in if", not r.ok and r.error.hint.contains("=="), str(r.error))

	r = PyInterp.run("if True:\nprint(1)\n")
	check("missing indent", not r.ok and r.error.kind == "縮排錯誤", str(r.error))

	r = PyInterp.run("print(1)\n    print(2)\n")
	check("extra indent", not r.ok and r.error.kind == "縮排錯誤", str(r.error))

	r = PyInterp.run("a = 3\nprint(\"走\" + a)\n")
	check("str+int", not r.ok and r.error.hint.contains("f-string"), str(r.error))

	r = PyInterp.run("print(\"hi)\n")
	check("unclosed string", not r.ok and r.error.message.contains("引號"), str(r.error))

	r = PyInterp.run("print(\"a\" \"b\", 1, True, None, 2.0, 7/2, 7//2, -7%3)\n")
	check("print values", r.ok and out_lines(r) == ["ab 1 True None 2.0 3.5 3 2"], str(out_lines(r)))

	r = PyInterp.run("print(\"a\"\n")
	check("unclosed paren", not r.ok, str(r.error))

	r = PyInterp.run("s = 0\nfor i in range(4):\n    s += i\nprint(s)\n")
	check("for range", r.ok and out_lines(r) == ["6"], str(r))

	r = PyInterp.run("while True:\n    pass\n")
	check("infinite loop", not r.ok and r.error.kind == "執行太久", str(r.error))

	r = PyInterp.run("import gopher\ngopher.walk(3)\n", {"modules": {"gopher": ["walk"]}})
	var calls: Array = r.trace.filter(func(t): return t.type == "call")
	check("module call", r.ok and calls.size() == 1 and calls[0].name == "gopher.walk" and calls[0].args == [3], str(r))

	r = PyInterp.run("import os\n")
	check("bad import", not r.ok and r.error.kind == "匯入錯誤", str(r.error))

	r = PyInterp.run("a = 4\nb = a + 1\n")
	var lines: Array = r.trace.filter(func(t): return t.type == "line")
	check("trace vars", lines.size() == 2 and lines[1].vars.get("a") == 4, str(lines))

	r = PyInterp.run("print(\"x\", end=\"\")\nprint(\"y\")\n")
	check("end kw", r.ok and out_lines(r) == ["xy"], str(out_lines(r)))

	r = PyInterp.run("x = 3\nif x > 1 and not x == 2:\n    print(f\"{x * 2}步\")\n")
	check("bool ops", r.ok and out_lines(r) == ["6步"], str(r))

	r = PyInterp.run("print(\"a\")  # 註解\n\n# 整行註解\nprint('b')\n")
	check("comments", r.ok and out_lines(r) == ["a", "b"], str(r))
