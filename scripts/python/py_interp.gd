class_name PyInterp
extends RefCounted
## 簡化版 Python 直譯器。整支程式先「跑完」並記錄 trace，再交給遊戲逐步演出。
## trace 事件：
##   {type:"line", line, vars}          執行到某一行（vars 為當下變數快照）
##   {type:"print", line, text}         print 輸出
##   {type:"input", line, prompt, value} input() 讀到一個回答（回答由 options.inputs 依序提供）
##   {type:"call", line, name, args}    呼叫遊戲模組函式（例如 gopher.walk）
##   {type:"error", line, ...}          執行期錯誤

const MAX_STEPS := 5000
const BUILTINS := ["print", "input", "len", "str", "int", "float", "abs", "range", "min", "max", "round", "bool"]

class PyError:
	var kind: String
	var line: int
	var message: String
	var hint: String
	func _init(k: String, l: int, m: String, h: String = "") -> void:
		kind = k
		line = l
		message = m
		hint = h

## 控制流程訊號
class BreakSignal:
	pass
class ContinueSignal:
	pass

var env: Dictionary = {}
var trace: Array = []
var outputs: Array = []
var steps := 0
var err: PyError = null
## 可 import 的遊戲模組：{"gopher": ["walk", "turn_left", ...]}
var modules: Dictionary = {}
## 允許使用的內建函式（任務可限制）
var allowed_builtins: Array = BUILTINS.duplicate()
## input() 的回答（依序取用）；用完了還要再 input() 就停下來，回傳 need_input 讓遊戲去問玩家
var inputs: Array = []
var input_pos := 0
var need_input: Dictionary = {}


## 執行程式。preset_vars 會在程式開始前放進變數表（目前未使用，隱藏測資改用替換題目給定行）。
static func run(source: String, options: Dictionary = {}) -> Dictionary:
	var parsed := PyParser.parse(source)
	if not parsed.error.is_empty():
		return {"ok": false, "error": parsed.error, "trace": [], "outputs": [], "ast": null, "env": {}}
	var it := PyInterp.new()
	it.modules = options.get("modules", {})
	if options.has("builtins"):
		it.allowed_builtins = options.builtins
	it.inputs = options.get("inputs", [])
	it._exec_block(parsed.ast.body)
	if not it.need_input.is_empty():
		it.err = null
	if not it.outputs.is_empty() and not it.outputs[-1].done:
		it.outputs[-1].done = true
		it.trace.append({"type": "print", "line": it.outputs[-1].line, "text": it.outputs[-1].text})
	var result := {"ok": it.err == null, "error": {}, "trace": it.trace, "outputs": it.outputs, "ast": parsed.ast, "env": it._snapshot(),
		"need_input": it.need_input}
	if it.err != null:
		result.error = {"kind": it.err.kind, "line": it.err.line, "col": 1,
			"message": "第 %d 行：%s" % [it.err.line, it.err.message], "hint": it.err.hint}
		it.trace.append({"type": "error", "line": it.err.line, "error": result.error})
	return result


func _snapshot() -> Dictionary:
	var snap := {}
	for k in env:
		var v = env[k]
		if v is Dictionary and v.has("__module__"):
			continue
		snap[k] = v.duplicate() if v is Array else v
	return snap


func _raise(kind: String, line: int, msg: String, hint: String = "") -> void:
	if err == null:
		err = PyError.new(kind, line, msg, hint)


# ---------------- 敘述 ----------------
## 回傳 null 表示正常，否則為 BreakSignal / ContinueSignal
func _exec_block(stmts: Array):
	for s in stmts:
		if err != null:
			return null
		var sig = _exec(s)
		if sig != null:
			return sig
	return null


func _exec(s: Dictionary):
	steps += 1
	if steps > MAX_STEPS:
		_raise("執行太久", s.line, "程式跑了太多步還沒結束", "是不是寫出了停不下來的迴圈？檢查 while 的條件會不會變成 False。")
		return null
	trace.append({"type": "line", "line": s.line, "vars": _snapshot()})
	match s.k:
		"Expr":
			_eval(s.value)
		"Assign":
			var v = _eval(s.value)
			if err == null:
				_assign(s.target, v)
		"AugAssign":
			var name: String = s.target.id
			if not env.has(name):
				_raise("名稱錯誤", s.line, "變數「%s」還沒有值，不能用「%s=」" % [name, s.op], "請先寫 %s = 0 給它一個初始值。" % name)
				return null
			var r = _eval(s.value)
			if err == null:
				env[name] = _binop(s.op, env[name], r, s.line)
		"Pass":
			pass
		"Break":
			return BreakSignal.new()
		"Continue":
			return ContinueSignal.new()
		"Import":
			if not modules.has(s.name):
				_raise("匯入錯誤", s.line, "找不到模組「%s」" % s.name, "這個任務可以匯入的模組：%s" % (", ".join(modules.keys()) if not modules.is_empty() else "（沒有）"))
				return null
			env[s.name] = {"__module__": s.name}
		"ImportFrom":
			if not modules.has(s.module):
				_raise("匯入錯誤", s.line, "找不到模組「%s」" % s.module)
				return null
			for nm in s.names:
				if not (nm in modules[s.module]):
					_raise("匯入錯誤", s.line, "模組「%s」裡沒有「%s」" % [s.module, nm])
					return null
				env[nm] = {"__func__": "%s.%s" % [s.module, nm]}
		"If":
			var t = _eval(s.test)
			if err != null:
				return null
			if _truthy(t):
				return _exec_block(s.body)
			elif not s.orelse.is_empty():
				if s.has("else_line"):
					trace.append({"type": "line", "line": s.else_line, "vars": _snapshot()})
				return _exec_block(s.orelse)
		"While":
			while err == null:
				var t2 = _eval(s.test)
				if err != null or not _truthy(t2):
					break
				var sig = _exec_block(s.body)
				if sig is BreakSignal:
					break
				steps += 1
				if steps > MAX_STEPS:
					_raise("執行太久", s.line, "while 迴圈一直停不下來", "檢查迴圈裡有沒有改變條件裡的變數。")
				trace.append({"type": "line", "line": s.line, "vars": _snapshot()})
		"For":
			var seq = _eval(s.iter)
			if err != null:
				return null
			if seq is String:
				seq = Array(seq.split(""))
			if not (seq is Array):
				_raise("型別錯誤", s.line, "for 後面要放可以一個一個拿出來的東西", "例如 range(3) 或串列 [1, 2, 3]。")
				return null
			for item in seq:
				if err != null:
					break
				env[s.var] = item
				var sig2 = _exec_block(s.body)
				if sig2 is BreakSignal:
					break
	return null


func _assign(target: Dictionary, v) -> void:
	match target.k:
		"Name":
			if target.id in BUILTINS:
				_raise("名稱錯誤", target.line, "「%s」是內建函式的名字，不能拿來當變數" % target.id, "換一個變數名稱吧，例如 %s_value。" % target.id)
				return
			env[target.id] = v
		"Index":
			var obj = _eval(target.obj)
			var idx = _eval(target.index)
			if obj is Array and idx is int:
				if idx < -obj.size() or idx >= obj.size():
					_raise("索引錯誤", target.line, "串列只有 %d 個元素，沒有第 %d 個" % [obj.size(), idx])
					return
				obj[idx] = v
			else:
				_raise("型別錯誤", target.line, "這個東西不能用 [ ] 修改")
		_:
			_raise("語法錯誤", target.line, "不能把值存進這裡")


# ---------------- 運算式 ----------------
func _eval(e):
	if err != null or e == null:
		return null
	match e.k:
		"Const":
			return e.value
		"Name":
			if env.has(e.id):
				return env[e.id]
			if e.id in BUILTINS:
				return {"__builtin__": e.id}
			_raise_name_error(e)
			return null
		"JoinedStr":
			var s := ""
			for part in e.parts:
				if part.k == "Const":
					s += part.value
				else:
					var v = _eval(part.value)
					s += py_str(v)
			return s
		"List":
			var arr: Array = []
			for it in e.items:
				arr.append(_eval(it))
			return arr
		"BinOp":
			var l = _eval(e.left)
			var r = _eval(e.right)
			if err != null:
				return null
			return _binop(e.op, l, r, e.line)
		"Unary":
			var v2 = _eval(e.operand)
			if not (v2 is int or v2 is float):
				_raise("型別錯誤", e.line, "「%s」只能放在數字前面" % e.op)
				return null
			return -v2 if e.op == "-" else v2
		"Not":
			return not _truthy(_eval(e.operand))
		"BoolOp":
			var lv = _eval(e.left)
			if e.op == "and":
				return lv if not _truthy(lv) else _eval(e.right)
			return lv if _truthy(lv) else _eval(e.right)
		"Compare":
			var left = _eval(e.left)
			for i in range(e.ops.size()):
				var right = _eval(e.rights[i])
				if err != null:
					return null
				if not _compare(e.ops[i], left, right, e.line):
					return false
				left = right
			return true
		"Call":
			return _call(e)
		"Attribute":
			var obj = _eval(e.obj)
			if obj is Dictionary and obj.has("__module__"):
				var mod: String = obj.__module__
				if e.attr in modules.get(mod, []):
					return {"__func__": "%s.%s" % [mod, e.attr]}
				_raise("屬性錯誤", e.line, "模組「%s」沒有「%s」" % [mod, e.attr], "可以用的有：%s" % ", ".join(modules.get(mod, [])))
				return null
			if obj is String and e.attr in ["upper", "lower", "strip", "replace", "split", "format"]:
				return {"__method__": e.attr, "self": obj}
			_raise("屬性錯誤", e.line, "這裡不能使用「.%s」" % e.attr)
			return null
		"Index":
			var o = _eval(e.obj)
			var idx = _eval(e.index)
			if err != null:
				return null
			if (o is Array or o is String) and idx is int:
				var n: int = o.length() if o is String else o.size()
				if idx < -n or idx >= n:
					_raise("索引錯誤", e.line, "只有 %d 個元素，沒有索引 %d" % [n, idx], "索引從 0 開始，最後一個是 %d。" % (n - 1))
					return null
				return o[idx if idx >= 0 else n + idx]
			_raise("型別錯誤", e.line, "這個東西不能用 [ ] 取值")
			return null
	_raise("語法錯誤", e.line, "目前還不支援這種寫法")
	return null


func _raise_name_error(e: Dictionary) -> void:
	var name: String = e.id
	var candidates: Array = env.keys() + BUILTINS + modules.keys()
	var best := ""
	var best_d := 99
	for c in candidates:
		var d := edit_distance(name, str(c))
		if d < best_d:
			best_d = d
			best = str(c)
	var hint := ""
	if best_d <= 2 and best != "":
		hint = "是不是要寫「%s」？" % best
	elif _has_cjk(name):
		hint = "如果「%s」是要說的話（文字），要用引號包起來，例如 \"%s\"。" % [name, name]
	else:
		hint = "變數要先用「=」給值才能使用，例如 %s = 1。" % name
	_raise("名稱錯誤", e.line, "找不到名稱「%s」" % name, hint)


func _call(e: Dictionary):
	var f = _eval(e.func)
	if err != null:
		return null
	var args: Array = []
	for a in e.args:
		args.append(_eval(a))
	var kwargs := {}
	for k in e.kwargs:
		kwargs[k] = _eval(e.kwargs[k])
	if err != null:
		return null
	if f is Dictionary and f.has("__builtin__"):
		return _builtin(f.__builtin__, args, kwargs, e.line)
	if f is Dictionary and f.has("__func__"):
		trace.append({"type": "call", "line": e.line, "name": f.__func__, "args": args})
		return null
	if f is Dictionary and f.has("__method__"):
		return _str_method(f.__method__, f.self, args, e.line)
	_raise("型別錯誤", e.line, "「%s」不是函式，不能用 ( ) 呼叫" % py_repr(f), "只有像 print 這樣的函式後面才能接括號。")
	return null


func _builtin(name: String, args: Array, kwargs: Dictionary, line: int):
	if not (name in allowed_builtins):
		_raise("尚未解鎖", line, "這個任務還不能使用「%s」" % name, "看看任務單上可以用哪些指令。")
		return null
	match name:
		"print":
			var sep: String = py_str(kwargs.get("sep", " "))
			var end: String = py_str(kwargs.get("end", "\n"))
			var parts: Array = []
			for a in args:
				parts.append(py_str(a))
			var text: String = sep.join(parts) + end
			# 以「行」為單位記錄輸出（end 不是換行時，和下一次 print 串在同一行）
			if not outputs.is_empty() and not outputs[-1].done:
				outputs[-1].text += text
			else:
				outputs.append({"line": line, "text": text, "done": false})
			var cur: Dictionary = outputs[-1]
			if cur.text.ends_with("\n"):
				cur.text = cur.text.substr(0, cur.text.length() - 1)
				cur.done = true
				trace.append({"type": "print", "line": cur.line, "text": cur.text})
			return null
		"input":
			var prompt: String = py_str(args[0]) if args.size() > 0 else ""
			# input() 之前沒換行的 print（end=""）先送出
			if not outputs.is_empty() and not outputs[-1].done:
				outputs[-1].done = true
				trace.append({"type": "print", "line": outputs[-1].line, "text": outputs[-1].text})
			if input_pos >= inputs.size():
				need_input = {"line": line, "prompt": prompt}
				_raise("等待輸入", line, "等待輸入")  # 用錯誤機制停下整支程式（run() 會清掉）
				return null
			var ans: String = str(inputs[input_pos])
			input_pos += 1
			trace.append({"type": "input", "line": line, "prompt": prompt, "value": ans})
			return ans
		"len":
			if args.size() != 1 or not (args[0] is String or args[0] is Array):
				_raise("型別錯誤", line, "len() 要放一個字串或串列")
				return null
			return args[0].length() if args[0] is String else args[0].size()
		"str":
			return py_str(args[0]) if args.size() > 0 else ""
		"int":
			if args.is_empty():
				return 0
			var v = args[0]
			if v is String:
				if v.strip_edges().is_valid_int():
					return int(v)
				_raise("數值錯誤", line, "「%s」不能轉成整數" % v, "int() 只能轉換像「3」這樣的數字文字。如果是 input() 讀進來的，回答時要輸入數字喔。")
				return null
			if v is bool:
				return 1 if v else 0
			return int(v)
		"float":
			return float(args[0]) if args.size() > 0 else 0.0
		"bool":
			return _truthy(args[0]) if args.size() > 0 else false
		"abs":
			return abs(args[0])
		"round":
			return int(round(args[0])) if args.size() == 1 else snappedf(args[0], pow(10, -args[1]))
		"min", "max":
			var src: Array = args[0] if args.size() == 1 and args[0] is Array else args
			if src.is_empty():
				_raise("數值錯誤", line, "%s() 裡面是空的" % name)
				return null
			var best = src[0]
			for v2 in src:
				if (name == "min" and v2 < best) or (name == "max" and v2 > best):
					best = v2
			return best
		"range":
			for a in args:
				if not (a is int):
					_raise("型別錯誤", line, "range() 裡面要放整數")
					return null
			var start := 0
			var stop := 0
			var step := 1
			if args.size() == 1:
				stop = args[0]
			elif args.size() >= 2:
				start = args[0]
				stop = args[1]
				if args.size() == 3:
					step = args[2]
			if step == 0:
				_raise("數值錯誤", line, "range() 的間隔不能是 0")
				return null
			var out: Array = []
			var i := start
			while (step > 0 and i < stop) or (step < 0 and i > stop):
				out.append(i)
				i += step
				if out.size() > MAX_STEPS:
					break
			return out
	return null


func _str_method(m: String, s: String, args: Array, line: int):
	match m:
		"upper": return s.to_upper()
		"lower": return s.to_lower()
		"strip": return s.strip_edges()
		"replace":
			if args.size() < 2:
				_raise("型別錯誤", line, "replace() 要放兩個字串")
				return null
			return s.replace(py_str(args[0]), py_str(args[1]))
		"split":
			return Array(s.split(" " if args.is_empty() else py_str(args[0]), args.is_empty() == false))
	return null


func _binop(op: String, l, r, line: int):
	var ln := l is int or l is float
	var rn := r is int or r is float
	if l is bool:
		l = 1 if l else 0
		ln = true
	if r is bool:
		r = 1 if r else 0
		rn = true
	match op:
		"+":
			if ln and rn:
				return l + r
			if l is String and r is String:
				return l + r
			if l is Array and r is Array:
				return l + r
			if (l is String and rn) or (ln and r is String):
				_raise("型別錯誤", line, "文字和數字不能直接用「+」相加",
					"可以改用 f-string，例如 f\"走了{a}步\"，或用 str(a) 把數字變成文字。")
				return null
		"-", "/", "//", "%", "**":
			if ln and rn:
				match op:
					"-": return l - r
					"**": return pow(l, r) if (l is float or r is float or r < 0) else int(pow(l, r))
				if r == 0:
					_raise("除以零", line, "不能除以 0", "檢查除數的變數是不是 0。")
					return null
				match op:
					"/": return float(l) / float(r)
					"//": return int(floor(float(l) / float(r))) if (l is int and r is int) else floor(float(l) / float(r))
					"%":
						if l is int and r is int:
							return ((l % r) + r) % r
						return fposmod(l, r)
		"*":
			if ln and rn:
				return l * r
			if l is String and r is int:
				return l.repeat(max(r, 0))
			if l is int and r is String:
				return r.repeat(max(l, 0))
	_raise("型別錯誤", line, "「%s」不能用在 %s 和 %s 之間" % [op, py_type(l), py_type(r)])
	return null


func _compare(op: String, l, r, line: int) -> bool:
	var ln := l is int or l is float or l is bool
	var rn := r is int or r is float or r is bool
	match op:
		"==":
			if ln and rn:
				return float(l) == float(r)
			return typeof(l) == typeof(r) and l == r
		"!=":
			return not _compare("==", l, r, line)
		"in":
			if r is String and l is String:
				return r.contains(l)
			if r is Array:
				return l in r
			_raise("型別錯誤", line, "in 的右邊要是字串或串列")
			return false
	if (ln and rn) or (l is String and r is String):
		match op:
			"<": return l < r
			">": return l > r
			"<=": return l <= r
			">=": return l >= r
	_raise("型別錯誤", line, "%s 和 %s 不能比大小" % [py_type(l), py_type(r)],
		"比大小的兩邊要都是數字。如果是文字，可以用 int() 轉成數字。")
	return false


func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String or v is Array:
		return not v.is_empty()
	return true


# ---------------- 工具 ----------------
static func py_str(v) -> String:
	if v == null:
		return "None"
	if v is bool:
		return "True" if v else "False"
	if v is float:
		if is_inf(v):
			return "inf" if v > 0 else "-inf"
		if v == floor(v) and abs(v) < 1e16:
			return "%d.0" % int(v)
		return str(v)
	if v is String:
		return v
	if v is Array:
		var parts: Array = []
		for x in v:
			parts.append(py_repr(x))
		return "[" + ", ".join(parts) + "]"
	if v is Dictionary:
		if v.has("__builtin__"):
			return "<built-in function %s>" % v.__builtin__
		if v.has("__module__"):
			return "<module '%s'>" % v.__module__
		if v.has("__func__"):
			return "<function %s>" % v.__func__
	return str(v)


static func py_repr(v) -> String:
	if v is String:
		return "'" + v.replace("\\", "\\\\").replace("'", "\\'") + "'"
	return py_str(v)


static func py_type(v) -> String:
	if v == null: return "None"
	if v is bool: return "布林值"
	if v is int: return "整數"
	if v is float: return "小數"
	if v is String: return "字串"
	if v is Array: return "串列"
	return "物件"


static func edit_distance(a: String, b: String) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0: return m
	if m == 0: return n
	var prev: Array = range(m + 1)
	for i in range(1, n + 1):
		var cur: Array = [i]
		for j in range(1, m + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
		prev = cur
	return prev[m]


static func _has_cjk(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false
