class_name TaskChecker
extends RefCounted
## 檢查器：一律「嚴格」列出所有偏差（findings），評分政策另外決定哪些算不過關。
## finding = {code, case, line, message, hint, ghost?}
## code 例：syntax.全形符號 / runtime.名稱錯誤 / action.fail / output.whitespace / goal.position / rule.must_use
##
## 評分政策（task.scoring.overrides 可覆寫，支援 "rule.*" 這種前綴）：
##   block = 不過關；warn = 過關但少一顆星；info = 只提醒

const DEFAULT_POLICY := {
	"syntax.*": "block",
	"runtime.*": "block",
	"action.*": "block",
	"output.*": "block",
	"goal.*": "block",
	"rule.given_var": "block",
	"rule.*": "warn",
	"speech.near": "info",
}


static func severity(task: Dictionary, code: String) -> String:
	var overrides: Dictionary = task.get("scoring", {}).get("overrides", {})
	for table in [overrides, DEFAULT_POLICY]:
		if table.has(code):
			return table[code]
		var prefix := code.split(".")[0] + ".*"
		if table.has(prefix):
			return table[prefix]
	return "warn"


static func evaluate(task: Dictionary, code: String) -> Dictionary:
	var findings: Array = []
	var cases: Array = []
	# 1. 語法：先剖析一次
	var parsed := PyParser.parse(code)
	if parsed.ast == null:
		var e: Dictionary = parsed.error
		findings.append({"code": "syntax." + e.kind, "case": "", "line": e.line, "message": e.message, "hint": e.hint})
		return _finish(task, findings, cases)
	# 2. 寫法規則
	findings.append_array(check_rules(task, parsed.ast, code))
	# 3. 每個測資：學生 vs 標準答案
	for test in task.get("tests", [{"name": "", "vars": {}}]):
		var ref := TaskRunner.run_case(task, task.reference, test)
		var stu := TaskRunner.run_case(task, code, test)
		var case_findings: Array = []
		var cname: String = test.get("name", "")
		if not stu.missing.is_empty():
			# 已由 rule.given_var 回報，這個測資無法套用
			cases.append({"name": cname, "hidden": test.get("hidden", false), "stu": stu, "ref": ref, "ok": false})
			continue
		if not stu.interp.ok:
			var er: Dictionary = stu.interp.error
			case_findings.append({"code": "runtime." + er.kind, "case": cname, "line": er.line, "message": er.message, "hint": er.hint})
		if not stu.action_fail.is_empty():
			var af: Dictionary = stu.action_fail
			case_findings.append({"code": "action.fail", "case": cname, "line": af.line, "message": "第 %d 行：%s" % [af.line, af.reason], "hint": af.hint})
		if task.get("print_role", "") != "dialogue":  # 對話任務：每一句已在 action.fail 對照過
			case_findings.append_array(compare_outputs(ref.outputs, stu.outputs, stu.interp.outputs, cname))
			case_findings.append_array(compare_goal(task, ref.world, stu.world, cname))
		# 對話裡有接近句型的句子 → 提醒
		for ev in stu.timeline:
			if ev.type == "action" and ev.result.get("near", "") != "":
				case_findings.append({"code": "speech.near", "case": cname, "line": ev.line,
					"message": "第 %d 行「%s」被當成對派派兔說的話" % [ev.line, ev.result.text],
					"hint": "如果是要做動作，句型是「%s」。" % ev.result.near})
		findings.append_array(case_findings)
		var ok := true
		for f in case_findings:
			if severity(task, f.code) == "block":
				ok = false
		cases.append({"name": cname, "hidden": test.get("hidden", false), "stu": stu, "ref": ref, "ok": ok})
	return _finish(task, findings, cases)


static func _finish(task: Dictionary, findings: Array, cases: Array) -> Dictionary:
	var blocks := 0
	var warns := 0
	for f in findings:
		f.severity = severity(task, f.code)
		if f.severity == "block":
			blocks += 1
		elif f.severity == "warn":
			warns += 1
	var passed := blocks == 0 and not cases.is_empty()
	var stars := 0
	if passed:
		stars = 3 if warns == 0 else 2
	return {"passed": passed, "stars": stars, "findings": findings, "cases": cases, "blocks": blocks, "warns": warns}


# ---------------- 輸出比對 ----------------
static func normalize_fullwidth(s: String) -> String:
	var out := s
	for k in PyLexer.FULLWIDTH:
		var v: String = PyLexer.FULLWIDTH[k]
		out = out.replace(k, " " if v == "空白" else v)
	return out


static func compare_outputs(exp: Array, got: Array, got_meta: Array, cname: String) -> Array:
	var out: Array = []
	var n: int = max(exp.size(), got.size())
	var reported := 0
	for i in range(n):
		if reported >= 3:
			break
		var line := 0
		if i < got_meta.size():
			line = got_meta[i].line
		if i >= got.size():
			out.append({"code": "output.missing", "case": cname, "line": 0,
				"message": "少說了第 %d 句：「%s」" % [i + 1, exp[i]], "hint": "程式要說的話比預期少。是不是漏了一行，或程式中途停下來了？"})
			reported += 1
			break
		if i >= exp.size():
			out.append({"code": "output.extra", "case": cname, "line": line,
				"message": "第 %d 行多說了一句「%s」" % [line, got[i]], "hint": "預期只有 %d 句話。" % exp.size()})
			reported += 1
			break
		var g: String = got[i]
		var e: String = exp[i]
		if g == e:
			continue
		reported += 1
		if g.strip_edges() == e.strip_edges():
			out.append({"code": "output.whitespace", "case": cname, "line": line,
				"message": "第 %d 行的話多了或少了空白：「%s」" % [line, g], "hint": "應該是「%s」，前後不要有空白。" % e})
		elif normalize_fullwidth(g) == normalize_fullwidth(e):
			out.append({"code": "output.punct", "case": cname, "line": line,
				"message": "第 %d 行的標點符號不一樣：「%s」" % [line, g], "hint": "應該是「%s」，注意全形和半形。" % e})
		elif PyInterp.edit_distance(g, e) <= max(2, e.length() / 4):
			out.append({"code": "output.typo", "case": cname, "line": line,
				"message": "第 %d 行說「%s」，和預期不一樣" % [line, g], "hint": "仔細對照，應該是「%s」。" % e})
		else:
			out.append({"code": "output.mismatch", "case": cname, "line": line,
				"message": "第 %d 句應該是「%s」，你的程式說了「%s」" % [i + 1, e, g], "hint": "檢查程式的順序和條件判斷。"})
	return out


static func compare_goal(task: Dictionary, ref_world: WorldModel, stu_world: WorldModel, cname: String) -> Array:
	var out: Array = []
	for uid in task.get("goal_items", []):
		if not ref_world.items.has(uid):
			continue
		var r: Dictionary = ref_world.items[uid]
		var s: Dictionary = stu_world.items[uid]
		var name: String = WorldModel.def_of(r.type).name
		if stu_world.holding == uid and ref_world.holding != uid:
			out.append({"code": "goal.holding", "case": cname, "line": 0,
				"message": "%s還抱在派派鼠手上" % name, "hint": "搬完要記得「放下」喔。", "ghost": {"uid": uid, "cell": [r.cell.x, r.cell.y]}})
		elif r.cell != s.cell:
			out.append({"code": "goal.position", "case": cname, "line": 0,
				"message": "%s應該在 (%d, %d)，現在在 (%d, %d)" % [name, r.cell.x, r.cell.y, s.cell.x, s.cell.y],
				"hint": "虛線影子是正確的位置。", "ghost": {"uid": uid, "cell": [r.cell.x, r.cell.y]}})
	return out


# ---------------- 寫法規則 ----------------
static func walk(node, visit: Callable) -> void:
	if node is Array:
		for x in node:
			walk(x, visit)
		return
	if not (node is Dictionary) or not node.has("k"):
		return
	visit.call(node)
	for key in node:
		var v = node[key]
		if v is Dictionary or v is Array:
			walk(v, visit)


static func check_rules(task: Dictionary, ast: Dictionary, code: String) -> Array:
	var out: Array = []
	var given: Array = task.get("given_vars", [])
	for rule in task.get("rules", []):
		match rule.id:
			"given_var":
				var name: String = rule.name
				var found := false
				for s in ast.body:
					if s.k == "Assign" and s.target.k == "Name" and s.target.id == name:
						found = true
				if not found:
					out.append({"code": "rule.given_var", "case": "", "line": 1,
						"message": "找不到題目給的變數 %s" % name,
						"hint": "請保留「%s = …」這一行，而且要寫在最外層（不要縮排）。派派狼要靠它換成別的值來檢查。" % name})
			"only_print":
				var bad := [0]
				walk(ast.body, func(n):
					if n.k == "Expr" and not (n.value.k == "Call" and n.value.func.k == "Name" and n.value.func.id == "print"):
						bad[0] = n.line if bad[0] == 0 else bad[0]
					elif n.k in ["Assign", "AugAssign", "If", "While", "For", "Import", "ImportFrom"]:
						if not (n.k == "Assign" and n.target.k == "Name" and n.target.id in given):
							bad[0] = n.line if bad[0] == 0 else bad[0])
				if bad[0] != 0:
					out.append({"code": "rule.only_print", "case": "", "line": bad[0],
						"message": "第 %d 行：這一題只能用 print()" % bad[0], "hint": "任務單規定只用 print()，一行說一句話。"})
			"must_use":
				var kind: String = rule.node
				var hit := [false]
				walk(ast.body, func(n):
					if kind == "Else":
						if n.k == "If" and n.has("else_line"):
							hit[0] = true
					elif n.k == kind:
						hit[0] = true)
				if not hit[0]:
					var label: String = rule.get("label", kind)
					out.append({"code": "rule.must_use", "case": "", "line": 0,
						"message": "這一題要練習 %s，但程式裡沒有用到" % label, "hint": "任務單的規定裡有寫要用 %s 喔。" % label})
			"must_use_op":
				var op: String = rule.op
				var hit2 := [false]
				walk(ast.body, func(n):
					if n.k == "Compare" and op in n.ops:
						hit2[0] = true)
				if not hit2[0]:
					out.append({"code": "rule.must_use_op", "case": "", "line": 0,
						"message": "這一題要用比較運算子「%s」" % op, "hint": "想想看任務單上的條件該怎麼寫成 Python。"})
			"var_in_print":
				var vname: String = rule.name
				var hit3 := [false]
				walk(ast.body, func(n):
					if n.k == "Call" and n.func.k == "Name" and n.func.id == "print":
						walk(n.args, func(m):
							if m.k == "Name" and m.id == vname:
								hit3[0] = true))
				if not hit3[0]:
					out.append({"code": "rule.var_in_print", "case": "", "line": 0,
						"message": "print() 裡沒有用到變數 %s" % vname, "hint": rule.get("hint", "數字不要寫死，用 f-string 把 {%s} 放進句子裡。" % vname)})
			"must_call":
				var fname: String = rule.name
				var hit4 := [false]
				walk(ast.body, func(n):
					if n.k == "Call" and n.func.k == "Name" and n.func.id == fname:
						hit4[0] = true)
				if not hit4[0]:
					out.append({"code": "rule.must_call", "case": "", "line": 0,
						"message": "這一題要用 %s()，但程式裡沒有用到" % fname, "hint": rule.get("hint", "任務單的規定裡有寫要用 %s() 喔。" % fname)})
			"must_comment":
				# 要自己寫一行註解：# 後面的內容要用 prefix 開頭（題目給的說明註解不算）
				var prefix: String = rule.prefix
				var ok := false
				for l in code.split("\n"):
					var t := l.strip_edges()
					if t.begins_with("#") and t.substr(1).strip_edges().begins_with(prefix):
						ok = true
				if not ok:
					out.append({"code": "rule.must_comment", "case": "", "line": 0,
						"message": "找不到「# %s…」這一行筆記" % prefix, "hint": rule.get("hint", "註解要用 # 開頭，後面接「%s」。" % prefix)})
			"max_lines":
				var cnt := 0
				for l in code.split("\n"):
					if l.strip_edges() != "" and not l.strip_edges().begins_with("#"):
						cnt += 1
				if cnt > int(rule.n):
					out.append({"code": "rule.max_lines", "case": "", "line": 0,
						"message": "程式有 %d 行，超過 %d 行" % [cnt, int(rule.n)], "hint": "試試看更精簡的寫法。"})
			"custom":
				var script = load(rule.script)
				if script != null:
					out.append_array(script.check(task, ast, code))
	return out
