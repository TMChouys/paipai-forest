class_name TaskRunner
extends RefCounted
## 任務執行：程式 → 直譯器 trace → 依本題的 print 角色轉成動作 → 在 WorldModel 上先算一遍。
## 產生的 timeline 交給畫面逐步演出。
## print_role = "dialogue"：對話任務。程式的 print()／input() 依序對照 task.dialogue 劇本，
## 說對了別人才會接話；說錯了聽的人會聽不懂，演出停在那裡。

const TASK_DIR := "res://data/tasks/"


static func list_tasks() -> Array:
	var out: Array = []
	var dir := DirAccess.open(TASK_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".json"):
			var t := load_task(TASK_DIR + fname)
			if not t.is_empty():
				out.append(t)
	out.sort_custom(func(a, b): return a.get("order", 0) < b.get("order", 0))
	return out


static func load_task(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("任務 JSON 解析失敗：" + path)
		return {}
	if int(data.get("schema", 0)) != 1:
		push_warning("任務 schema 版本不同：" + path)
	return data


# ---------------- 題目給定變數的替換（隱藏測資用）----------------
static func literal(v) -> String:
	if v is bool:
		return "True" if v else "False"
	if v is float and v == floor(v):
		return str(int(v))
	if v is String:
		return "\"" + v + "\""
	return str(v)


## 把學生程式裡「第一個 name = …」那一行的值換掉。回傳 {code, missing:[...]}。
static func substitute_given(code: String, vars: Dictionary) -> Dictionary:
	var missing: Array = []
	if vars.is_empty():
		return {"code": code, "missing": missing}
	var parsed := PyParser.parse(code)
	if parsed.ast == null:
		return {"code": code, "missing": missing}
	var lines := code.replace("\r\n", "\n").split("\n")
	for name in vars:
		var found := -1
		for s in parsed.ast.body:
			if s.k == "Assign" and s.target.k == "Name" and s.target.id == name:
				found = s.line
				break
		if found < 0:
			missing.append(name)
			continue
		var old: String = lines[found - 1]
		var indent := old.substr(0, old.length() - old.strip_edges(true, false).length())
		var comment := ""
		var hash_pos := old.find("#")
		if hash_pos >= 0 and not old.substr(0, hash_pos).contains("\""):
			comment = "  " + old.substr(hash_pos)
		lines[found - 1] = indent + name + " = " + literal(vars[name]) + comment
	return {"code": "\n".join(lines), "missing": missing}


# ---------------- 句型 ----------------
static func compile_patterns(task: Dictionary) -> Array:
	var out: Array = []
	for p in task.get("patterns", []):
		var say: String = p.say
		var params: Array = []
		var rx_src := "^"
		var i := 0
		while i < say.length():
			if say[i] == "{":
				var close := say.find("}", i)
				params.append(say.substr(i + 1, close - i - 1))
				rx_src += "(-?\\d+)"
				i = close + 1
				continue
			var c := say[i]
			if "\\^$.|?*+()[]{}".contains(c):
				rx_src += "\\" + c
			else:
				rx_src += c
			i += 1
		rx_src += "$"
		var rx := RegEx.new()
		rx.compile(rx_src)
		out.append({"rx": rx, "say": say, "act": p.act, "args": p.get("args", {}), "params": params, "desc": p.get("desc", "")})
	return out


static func match_sentence(patterns: Array, text: String) -> Dictionary:
	for p in patterns:
		var m: RegExMatch = p.rx.search(text)
		if m != null:
			var args: Dictionary = p.args.duplicate()
			for i in range(p.params.size()):
				args[p.params[i]] = int(m.get_string(i + 1))
			return {"act": p.act, "args": args, "say": p.say}
	return {}


## 找最像的句型（給「聽不懂」的提示用）
static func nearest_sentence(patterns: Array, text: String) -> String:
	var best := ""
	var best_d := 999
	var num_rx := RegEx.new()
	num_rx.compile("-?\\d+")
	var num := num_rx.search(text)
	for p in patterns:
		var cand: String = p.say
		if p.params.size() > 0:
			cand = cand.replace("{%s}" % p.params[0], num.get_string() if num != null else "2")
		var d := PyInterp.edit_distance(text.strip_edges(), cand)
		if d < best_d:
			best_d = d
			best = cand
	if best_d <= max(2, best.length() / 2):
		return best
	return ""


# ---------------- 執行一個測資 ----------------
static func run_case(task: Dictionary, code: String, test: Dictionary) -> Dictionary:
	var sub := substitute_given(code, test.get("vars", {}))
	var interp := PyInterp.run(sub.code, {"builtins": task.get("builtins", PyInterp.BUILTINS), "modules": task.get("modules", {}),
		"inputs": test.get("inputs", [])})
	if task.get("print_role", "") == "dialogue":
		return _run_dialogue(task, sub, interp, test)
	var world := WorldModel.from_layout(task.room)
	var patterns := compile_patterns(task)
	var role: String = task.get("print_role", "action")
	var timeline: Array = []
	var action_fail: Dictionary = {}
	for ev in interp.trace:
		if not action_fail.is_empty():
			break
		match ev.type:
			"line", "error":
				timeline.append(ev)
			"print":
				timeline.append(ev)
				var m := {} if role == "speech" else match_sentence(patterns, ev.text)
				var res: Dictionary
				if not m.is_empty():
					res = world.apply(m.act, m.args)
				elif role == "action":
					var near := nearest_sentence(patterns, ev.text)
					res = {"ok": false, "act": "confused", "text": ev.text,
						"reason": "派派鼠聽不懂「%s」" % ev.text,
						"hint": ("是不是要說「%s」？" % near) if near != "" else "請對照句型表，說的話要一字不差。"}
				else:
					res = world.apply("say", {"text": ev.text})
					var near2 := nearest_sentence(patterns, ev.text)
					if near2 != "" and PyInterp.edit_distance(ev.text, near2) <= 2:
						res.near = near2
				timeline.append({"type": "action", "line": ev.line, "result": res})
				if not res.ok:
					action_fail = {"line": ev.line, "reason": res.reason, "hint": res.get("hint", ""), "act": res.act}
			"call":
				timeline.append(ev)
	var outs: Array = []
	for o in interp.outputs:
		outs.append(o.text)
	return {"code": sub.code, "missing": sub.missing, "interp": interp, "timeline": timeline,
		"world": world, "outputs": outs, "action_fail": action_fail, "need_input": {}}


# ---------------- 對話任務 ----------------
const NAMES := {"gopher": "派派鼠", "wolf": "派派狼", "rabbit": "派派兔", "tanuki": "狸老闆", "turtle": "慢慢館長", "crow": "拍拍鳥"}


static func _run_dialogue(task: Dictionary, sub: Dictionary, interp: Dictionary, test: Dictionary) -> Dictionary:
	# 標準答案用同一組測資（同樣的變數、同樣的回答）跑一次 → 每一句「應該」說什麼
	var ref_sub := substitute_given(task.reference, test.get("vars", {}))
	var ref := PyInterp.run(ref_sub.code, {"builtins": task.get("builtins", PyInterp.BUILTINS), "inputs": test.get("inputs", [])})
	var expected: Array = []
	for ev in ref.trace:
		if ev.type == "print":
			expected.append(ev.text)
		elif ev.type == "input":
			expected.append(ev.prompt)
	if not ref.need_input.is_empty():
		expected.append(ref.need_input.prompt)
	var env: Dictionary = ref.env
	var beats: Array = task.get("dialogue", [])
	var st := {"bi": 0, "k": 0}
	var timeline: Array = []
	var action_fail: Dictionary = {}
	var need: Dictionary = {}
	for ev in interp.trace:
		if not action_fail.is_empty():
			break
		match ev.type:
			"line", "error":
				timeline.append(ev)
			"print", "input":
				_emit_npc_lines(beats, st, timeline, env)  # 先演完別人的台詞，輸出視窗的順序才會和氣泡一致
				timeline.append(ev)
				var got: String = ev.text if ev.type == "print" else ev.prompt
				var res := _match_beat(beats, st, expected, ev.type, got)
				if res.ok and ev.type == "input":
					res.answer = ev.value
				timeline.append({"type": "action", "line": ev.line, "result": res})
				if not res.ok:
					action_fail = {"line": ev.line, "reason": res.reason, "hint": res.hint, "act": res.act}
	if action_fail.is_empty() and interp.ok:
		_emit_npc_lines(beats, st, timeline, env)
		if not interp.need_input.is_empty():
			# 程式停在 input()：先確認問的話對不對，再請玩家回答
			var ni: Dictionary = interp.need_input
			var res2 := _match_beat(beats, st, expected, "input", ni.prompt)
			if not res2.ok:
				timeline.append({"type": "action", "line": ni.line, "result": res2})
				action_fail = {"line": ni.line, "reason": res2.reason, "hint": res2.hint, "act": res2.act}
			elif test.get("interactive", false):
				need = {"line": ni.line, "prompt": ni.prompt, "who": res2.who}
			else:
				var res3 := {"ok": false, "act": "dlg_fail", "who": res2.who, "text": ni.prompt,
					"reason": "%s的問題已經問完了，程式卻還在等回答" % NAMES.get(res2.who, ""), "hint": "檢查 input() 是不是多寫了。"}
				timeline.append({"type": "action", "line": ni.line, "result": res3})
				action_fail = {"line": ni.line, "reason": res3.reason, "hint": res3.hint, "act": res3.act}
		elif st.bi < beats.size():
			var b: Dictionary = beats[st.bi]
			var what := "用 input() 讓%s問問題" % NAMES.get(b.who, "") if b.get("ask", false) else "派派鼠回答"
			var exp: String = expected[st.k] if st.k < expected.size() else ""
			var res4 := {"ok": false, "act": "dlg_fail", "who": _listener(beats, st.bi), "text": "",
				"reason": "對話還沒結束：接下來應該%s「%s」" % [what, exp], "hint": "照著註解，把每一句都寫成程式。"}
			timeline.append({"type": "action", "line": 0, "result": res4})
			action_fail = {"line": 0, "reason": res4.reason, "hint": res4.hint, "act": res4.act}
	var outs: Array = []
	for o in interp.outputs:
		outs.append(o.text)
	return {"code": sub.code, "missing": sub.missing, "interp": interp, "timeline": timeline,
		"world": WorldModel.from_layout(task.room), "outputs": outs, "action_fail": action_fail, "need_input": need}


## 把下一個「要程式說的話」之前的 NPC 台詞都放進 timeline
static func _emit_npc_lines(beats: Array, st: Dictionary, timeline: Array, env: Dictionary) -> void:
	while st.bi < beats.size():
		var b: Dictionary = beats[st.bi]
		if b.who == "gopher" or b.get("ask", false):
			return
		timeline.append({"type": "action", "line": 0, "result": {"ok": true, "act": "say", "who": b.who, "text": fill(b.say, env)}})
		st.bi += 1


## 台詞裡的 {變數} 換成標準答案算出來的值
static func fill(text: String, env: Dictionary) -> String:
	var out := text
	for k in env:
		out = out.replace("{%s}" % k, PyInterp.py_str(env[k]))
	return out


## 程式這句話（print 的內容或 input 的問題）對照劇本
static func _match_beat(beats: Array, st: Dictionary, expected: Array, kind: String, got: String) -> Dictionary:
	if st.bi >= beats.size():
		return {"ok": false, "act": "dlg_fail", "who": _listener(beats, st.bi), "text": got, "by_gopher": kind == "print",
			"reason": "大家都說完了，程式卻多說了「%s」" % got, "hint": "對話只有註解上的那幾句，多的請刪掉。"}
	var b: Dictionary = beats[st.bi]
	var want := "input" if b.get("ask", false) else "print"
	var exp: String = expected[st.k] if st.k < expected.size() else ""
	if kind != want:
		var why := ("這裡應該用 input() 讓%s問：「%s」" % [NAMES.get(b.who, ""), exp]) if want == "input" 			else ("這裡應該用 print() 讓派派鼠回答：「%s」" % exp)
		return {"ok": false, "act": "dlg_fail", "who": _listener(beats, st.bi), "text": got, "by_gopher": kind == "print", "reason": why, "hint": "照著註解的順序一句一句寫。"}
	if got != exp:
		var hint := "註解上寫的是「%s」，要一字不差。" % exp
		if got.strip_edges() == exp.strip_edges():
			hint = "前後多了或少了空白，應該是「%s」。" % exp
		elif TaskChecker.normalize_fullwidth(got) == TaskChecker.normalize_fullwidth(exp):
			hint = "標點符號不一樣（全形／半形），應該是「%s」。" % exp
		var who: String = b.who if want == "input" else _listener(beats, st.bi)
		var reason := ("%s不知道要問什麼：「%s」" % [NAMES.get(who, ""), got]) if want == "input" 			else ("%s聽不懂「%s」" % [NAMES.get(who, ""), got])
		return {"ok": false, "act": "dlg_fail", "who": who, "text": got, "by_gopher": kind == "print", "reason": reason, "hint": hint}
	st.bi += 1
	st.k += 1
	if want == "input":
		return {"ok": true, "act": "ask", "who": b.who, "text": got}
	return {"ok": true, "act": "say", "who": "gopher", "text": got}


## 派派鼠這句話是說給誰聽的：前面最後一個開口的角色（他在等回答）；沒有就往後找
static func _listener(beats: Array, from: int) -> String:
	for i in range(min(from, beats.size()) - 1, -1, -1):
		if beats[i].who != "gopher":
			return beats[i].who
	for i in range(from, beats.size()):
		if beats[i].who != "gopher":
			return beats[i].who
	return "wolf"
