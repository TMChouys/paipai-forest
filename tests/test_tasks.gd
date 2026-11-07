extends RefCounted
## 任務與檢查器測試：每份需求單的標準答案必須三星過關，常見錯誤必須被抓到。


func codes(rep: Dictionary) -> Array:
	var a: Array = []
	for f in rep.findings:
		a.append(f.code)
	return a


func run(t) -> void:
	var tasks := TaskRunner.list_tasks()
	t.check("10 tasks loaded", tasks.size() == 10, str(tasks.size()))
	var by_id := {}
	for task in tasks:
		by_id[task.id] = task
		var rep := TaskChecker.evaluate(task, task.reference)
		t.check("reference passes 3★: " + task.id, rep.passed and rep.stars == 3, str(codes(rep)) + " " + str(rep.findings))
		# 每個測資的標準答案都不能有動作失敗
		for c in rep.cases:
			t.check("ref no action fail: %s/%s" % [task.id, c.name], c.ref.action_fail.is_empty(), str(c.ref.action_fail))

	# 鎮中心的任務
	var tw2: Dictionary = by_id.TW2_member_card
	var rw2 := TaskChecker.evaluate(tw2, "name = \"派派鼠\"
print(\"派派鼠\")
print(\"派派鼠\")
")
	t.check("TW2 hardcoded name fails hidden", not rw2.passed and "rule.var_in_print" in codes(rw2), str(codes(rw2)))
	var tw3: Dictionary = by_id.TW3_library_note
	var rw3 := TaskChecker.evaluate(tw3, "print(\"好的，我會小聲。\")
")
	t.check("TW3 missing comment", not rw3.passed and "rule.must_comment" in codes(rw3), str(codes(rw3)))
	rw3 = TaskChecker.evaluate(tw3, "print(\"借書：森林植物圖鑑\")
print(\"好的，我會小聲。\")
")
	t.check("TW3 note spoken aloud fails", not rw3.passed, str(codes(rw3)))
	var tw1: Dictionary = by_id.TW1_group_photo
	var rw1 := TaskChecker.evaluate(tw1, "print(\"派派鼠\")
print(\"派派狼\")
print(\"派派兔\")
")
	t.check("TW1 wrong order fails", not rw1.passed, str(codes(rw1)))

	var t1: Dictionary = by_id.T01_print
	var rep1 := TaskChecker.evaluate(t1, "print（\"走到椅子\"）\n")
	t.check("T1 fullwidth -> syntax", not rep1.passed and codes(rep1)[0] == "syntax.全形符號", str(codes(rep1)))
	rep1 = TaskChecker.evaluate(t1, "print(\"走到椅子\")\nprint(\"搬起\")\nprint(\"走到窗戶\")\nprint(\"放下\")\n")
	t.check("T1 typo -> action fail with hint", not rep1.passed and "action.fail" in codes(rep1), str(rep1.findings))
	var hint_ok := false
	for f in rep1.findings:
		if f.code == "action.fail" and f.hint.contains("走到窗邊"):
			hint_ok = true
	t.check("T1 typo hint suggests 走到窗邊", hint_ok, str(rep1.findings))
	rep1 = TaskChecker.evaluate(t1, "print(\"走到椅子\")\nprint(\"搬起\")\nprint(\"走到窗邊\")\n")
	t.check("T1 forgot put_down", not rep1.passed and "goal.holding" in codes(rep1), str(codes(rep1)))
	rep1 = TaskChecker.evaluate(t1, "print(\"放下\")\n")
	t.check("T1 put without holding -> action", not rep1.passed and "action.fail" in codes(rep1), str(codes(rep1)))

	var t2: Dictionary = by_id.T02_variable
	var rep2 := TaskChecker.evaluate(t2, "a = 4\nprint(\"走到長桌\")\nprint(\"向前推4格\")\nprint(\"學姊，長桌往前推了4格\")\n")
	t.check("T2 hardcoded fails hidden", not rep2.passed, str(codes(rep2)))
	var hidden_fail := false
	for c in rep2.cases:
		if c.hidden and not c.ok:
			hidden_fail = true
	t.check("T2 hidden case marked failed", hidden_fail)
	t.check("T2 hardcoded warns var_in_print", "rule.var_in_print" in codes(rep2), str(codes(rep2)))
	rep2 = TaskChecker.evaluate(t2, "print(\"走到長桌\")\nprint(\"向前推4格\")\n")
	t.check("T2 missing given var", "rule.given_var" in codes(rep2) and not rep2.passed, str(codes(rep2)))
	rep2 = TaskChecker.evaluate(t2, "a = 4\nprint(\"走到長桌\")\nprint(\"向前推\" + str(a) + \"格\")\nprint(\"學姊，長桌往前推了\" + str(a) + \"格\")\n")
	t.check("T2 str() concat passes but warns no fstring", rep2.passed and rep2.stars == 2 and "rule.must_use" in codes(rep2), str(codes(rep2)))
	rep2 = TaskChecker.evaluate(t2, "a = 4\nprint(\"走到長桌\")\nprint(f\"向前推{a}格\")\nprint(f\"學姊，長桌往前推了{a}格 \")\n")
	t.check("T2 trailing space flagged", "output.whitespace" in codes(rep2), str(codes(rep2)))
	rep2 = TaskChecker.evaluate(t2, "a = 4\nprint(\"走到長桌\")\nprint(f\"向前推{a}個\")\nprint(f\"學姊，長桌往前推了{a}格\")\n")
	t.check("T2 near speech flagged", "speech.near" in codes(rep2) and not rep2.passed, str(codes(rep2)))

	var t3: Dictionary = by_id.T03_if_rain
	var rep3 := TaskChecker.evaluate(t3, "rain = True\nprint(\"走到傘架\")\nprint(\"搬起\")\nprint(\"走到門口\")\nprint(\"放下\")\n")
	t.check("T3 no-if fails hidden sunny", not rep3.passed and "goal.position" in codes(rep3), str(codes(rep3)))
	var ghost := false
	for f in rep3.findings:
		if f.has("ghost"):
			ghost = true
	t.check("T3 ghost provided", ghost)
	rep3 = TaskChecker.evaluate(t3, "rain = True\nif rain == True:\n    print(\"走到傘架\")\n    print(\"搬起\")\n    print(\"走到門口\")\n    print(\"放下\")\nelse:\n    print(\"走到花盆\")\n    print(\"搬起\")\n    print(\"走到門口\")\n    print(\"放下\")\n")
	t.check("T3 rain == True passes", rep3.passed and rep3.stars == 3, str(codes(rep3)))

	var s1: Dictionary = by_id.S01_crate_weight
	var rep4 := TaskChecker.evaluate(s1, s1.reference.replace("w > 5", "w >= 5"))
	t.check("S1 >= fails boundary", not rep4.passed, str(codes(rep4)))
	rep4 = TaskChecker.evaluate(s1, s1.reference.replace("w > 5", "5 < w"))
	t.check("S1 5 < w passes, warns op", rep4.passed and "rule.must_use_op" in codes(rep4), str(codes(rep4)))

	var sub := TaskRunner.substitute_given("a = 4  # 今天\nprint(a)\n", {"a": 2})
	t.check("substitute keeps comment", sub.code.begins_with("a = 2  # 今天"), sub.code)

	# ---- 對話任務 ----
	var d1: Dictionary = by_id.D01_hello
	var rd := TaskChecker.evaluate(d1, "print(\"你好！我是派派鼠。\")
print(\"學姊好!請多指教。\")
print(\"謝謝派狼老大！\")
")
	t.check("D1 halfwidth ! -> listener confused", not rd.passed and "action.fail" in codes(rd), str(codes(rd)))
	var punct_hint := false
	for f in rd.findings:
		if f.code == "action.fail" and f.hint.contains("全形") and f.message.contains("派派兔聽不懂"):
			punct_hint = true
	t.check("D1 hint mentions fullwidth, rabbit is listener", punct_hint, str(rd.findings))
	rd = TaskChecker.evaluate(d1, "print(\"你好！我是派派鼠。\")
")
	t.check("D1 unfinished dialogue fails", not rd.passed and "action.fail" in codes(rd), str(codes(rd)))
	var tl: Array = TaskRunner.run_case(d1, d1.reference, d1.tests[0]).timeline
	var speakers: Array = []
	for ev in tl:
		if ev.type == "action":
			speakers.append(ev.result.who)
	t.check("D1 timeline speakers in script order", speakers == ["wolf", "gopher", "rabbit", "gopher", "wolf", "gopher", "rabbit"], str(speakers))

	var d2: Dictionary = by_id.D02_acorns
	var r2 := TaskChecker.evaluate(d2, "bags = 3
per_bag = 12
print(\"我帶了3袋，每袋12顆！\")
print(\"一共36顆橡果！\")
print(\"好呀，分你18顆！\")
")
	t.check("D2 hardcoded numbers fail hidden", not r2.passed, str(codes(r2)))
	var wolf_line := ""
	for ev in TaskRunner.run_case(d2, d2.reference, d2.tests[2]).timeline:
		if ev.type == "action" and ev.result.who == "wolf" and ev.result.text.contains("分我一半"):
			wolf_line = ev.result.text
	t.check("D2 npc line filled with computed total", wolf_line == "35顆！分我一半好不好？", wolf_line)

	var d3: Dictionary = by_id.D03_questions
	var r3 := TaskChecker.evaluate(d3, "food = input(\"你最喜歡吃什麼？\")
print(f\"我最喜歡吃{food}！\")
n = input(\"你一天吃幾顆橡果？\")
print(f\"我一天吃{n}顆，一個禮拜吃{n * 7}顆！\")
")
	t.check("D3 forgot int() fails", not r3.passed, str(codes(r3)))
	# 互動執行：還沒有回答 → 停在第一個 input()，等玩家回答
	var live := TaskRunner.run_case(d3, d3.reference, {"name": "練習", "vars": {}, "inputs": [], "interactive": true})
	t.check("D3 interactive stops at first input", live.need_input.get("prompt", "") == "你最喜歡吃什麼？" and live.action_fail.is_empty(), str(live.need_input) + str(live.action_fail))
	live = TaskRunner.run_case(d3, d3.reference, {"name": "練習", "vars": {}, "inputs": ["草莓"], "interactive": true})
	t.check("D3 interactive second question", live.need_input.get("prompt", "") == "你一天吃幾顆橡果？", str(live.need_input))
	live = TaskRunner.run_case(d3, d3.reference, {"name": "練習", "vars": {}, "inputs": ["草莓", "4"], "interactive": true})
	var last_print := ""
	for o in live.outputs:
		last_print = o
	t.check("D3 interactive answers used", live.need_input.is_empty() and live.action_fail.is_empty() and last_print == "我一天吃4顆，一個禮拜吃28顆！", last_print + str(live.action_fail))
	live = TaskRunner.run_case(d3, "food = input(\"你喜歡吃什麼？\")
", {"name": "練習", "vars": {}, "inputs": [], "interactive": true})
	t.check("D3 wrong question caught before asking", live.need_input.is_empty() and not live.action_fail.is_empty(), str(live.action_fail))
