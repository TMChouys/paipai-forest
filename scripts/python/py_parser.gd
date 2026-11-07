class_name PyParser
extends RefCounted
## 簡化版 Python 剖析器：token → AST（以 Dictionary 表示，每個節點都有 k 與 line）。

var toks: Array
var p := 0
var error: Dictionary = {}


static func parse(source: String) -> Dictionary:
	var lx := PyLexer.tokenize(source)
	if not lx.error.is_empty():
		return {"ast": null, "error": lx.error}
	var ps := PyParser.new()
	ps.toks = lx.tokens
	var body := ps._program()
	if not ps.error.is_empty():
		return {"ast": null, "error": ps.error}
	return {"ast": {"k": "Module", "body": body, "line": 1}, "error": {}}


## 解析單一運算式（f-string 內的 {…} 使用）
static func parse_expr(source: String, line: int) -> Dictionary:
	var lx := PyLexer.tokenize(source)
	if not lx.error.is_empty():
		var e: Dictionary = lx.error
		e.line = line
		return {"ast": null, "error": e}
	var ps := PyParser.new()
	ps.toks = lx.tokens
	for t in ps.toks:
		t.line = line
	var node = ps._expr()
	if ps.error.is_empty() and ps._peek().t != "NEWLINE" and ps._peek().t != "EOF":
		ps._fail("f-string 的 {} 裡面只能放一個運算式", "例如 f\"走了{a}步\"。")
	if not ps.error.is_empty():
		return {"ast": null, "error": ps.error}
	return {"ast": node, "error": {}}


# ---------------- 工具 ----------------
func _peek(o: int = 0) -> Dictionary:
	return toks[min(p + o, toks.size() - 1)]


func _next() -> Dictionary:
	var t: Dictionary = toks[p]
	if p < toks.size() - 1:
		p += 1
	return t


func _is(t: String, v = null, o: int = 0) -> bool:
	var tk := _peek(o)
	if tk.t != t:
		return false
	return v == null or tk.v == v


func _accept(t: String, v = null) -> bool:
	if _is(t, v):
		_next()
		return true
	return false


func _fail(msg: String, hint: String = "", kind: String = "語法錯誤") -> void:
	if error.is_empty():
		var tk := _peek()
		error = {"kind": kind, "line": tk.line, "col": tk.col, "message": "第 %d 行：%s" % [tk.line, msg], "hint": hint}
	# 跳到結尾避免無限迴圈
	p = toks.size() - 1


func _expect(t: String, v, msg: String, hint: String = "") -> Dictionary:
	if _is(t, v):
		return _next()
	_fail(msg, hint)
	return _peek()


# ---------------- 敘述 ----------------
func _program() -> Array:
	var body: Array = []
	while error.is_empty() and not _is("EOF"):
		if _accept("NEWLINE"):
			continue
		if _is("INDENT"):
			_fail("這一行多了縮排", "只有在 if / else / while / for 底下的程式才需要縮排。", "縮排錯誤")
			break
		var s = _statement()
		if s != null:
			body.append(s)
	return body


func _statement():
	var tk := _peek()
	if tk.t == "KEYWORD":
		match tk.v:
			"if": return _if_stmt()
			"while": return _while_stmt()
			"for": return _for_stmt()
			"elif", "else":
				_fail("「%s」前面沒有對應的 if" % tk.v, "elif / else 要和上面的 if 對齊（縮排一樣）。")
				return null
	var s = _simple()
	if error.is_empty() and not _accept("NEWLINE"):
		if _is("EOF"):
			return s
		var bad := _peek()
		if bad.t == "STRING" or bad.t == "NAME" or bad.t == "NUMBER" or bad.t == "FSTRING":
			_fail("一行裡面出現了兩段沒有連起來的東西", "是不是少了逗號、加號，或右括號「)」？")
		else:
			_fail("這裡出現了多餘的「%s」" % str(bad.v), "請檢查這一行的寫法。")
	return s


func _simple():
	var tk := _peek()
	var line: int = tk.line
	if tk.t == "KEYWORD":
		match tk.v:
			"pass":
				_next()
				return {"k": "Pass", "line": line}
			"break":
				_next()
				return {"k": "Break", "line": line}
			"continue":
				_next()
				return {"k": "Continue", "line": line}
			"import":
				_next()
				var nm := _expect("NAME", null, "import 後面要接模組名稱", "例如 import gopher")
				return {"k": "Import", "name": nm.v, "line": line}
			"from":
				_next()
				var mod := _expect("NAME", null, "from 後面要接模組名稱", "例如 from gopher import walk")
				_expect("KEYWORD", "import", "少了 import", "例如 from gopher import walk")
				var names: Array = []
				names.append(_expect("NAME", null, "import 後面要接名稱").v)
				while _accept("OP", ","):
					names.append(_expect("NAME", null, "逗號後面要接名稱").v)
				return {"k": "ImportFrom", "module": mod.v, "names": names, "line": line}
			"def", "return":
				_fail("目前的任務還不能使用「%s」" % tk.v, "等學到函式的單元再解鎖喔！")
				return null
	var target = _expr()
	if not error.is_empty():
		return null
	if _is("OP", "="):
		_next()
		if target.k != "Name" and target.k != "Attribute" and target.k != "Index":
			_fail("等號「=」左邊只能放變數名稱", "例如 a = 4。若是要比較是否相等，請用「==」，而且要放在 if 裡。")
			return null
		var value = _expr()
		return {"k": "Assign", "target": target, "value": value, "line": line}
	for op in ["+=", "-=", "*=", "/=", "%=", "//=", "**="]:
		if _is("OP", op):
			_next()
			if target.k != "Name":
				_fail("「%s」左邊只能放變數名稱" % op)
				return null
			var v2 = _expr()
			return {"k": "AugAssign", "target": target, "op": op.substr(0, op.length() - 1), "value": v2, "line": line}
	return {"k": "Expr", "value": target, "line": line}


func _block(owner: String) -> Array:
	if not _is("OP", ":"):
		if _is("OP", "="):
			_fail("%s 的條件裡用了「=」" % owner, "判斷「是否相等」要用兩個等號「==」，一個「=」是把值存進變數。")
		else:
			_fail("%s 這一行的最後少了冒號「:」" % owner, "例如 if rain:")
		return []
	_next()
	if not _is("NEWLINE"):
		# 同一行的簡單敘述：if x: print(1)
		var s = _simple()
		_accept("NEWLINE")
		return [s] if s != null else []
	_next()
	while _accept("NEWLINE"):
		pass
	if not _is("INDENT"):
		_fail("%s 底下的程式要縮排" % owner, "在 %s 下一行的開頭空 4 格，表示「這些程式屬於它」。" % owner, "縮排錯誤")
		return []
	_next()
	var body: Array = []
	while error.is_empty() and not _is("DEDENT") and not _is("EOF"):
		if _accept("NEWLINE"):
			continue
		if _is("INDENT"):
			_fail("這一行多了縮排", "同一個區塊裡的程式要對齊。", "縮排錯誤")
			break
		var s2 = _statement()
		if s2 != null:
			body.append(s2)
	_accept("DEDENT")
	return body


func _if_stmt():
	var line: int = _next().line
	var test = _expr()
	var body := _block("if")
	var node := {"k": "If", "test": test, "body": body, "orelse": [], "line": line}
	if not error.is_empty():
		return node
	if _is("KEYWORD", "elif"):
		node.orelse = [_if_stmt()]
		node.orelse[0].is_elif = true
	elif _is("KEYWORD", "else"):
		var else_line: int = _next().line
		node.else_line = else_line
		node.orelse = _block("else")
	return node


func _while_stmt():
	var line: int = _next().line
	var test = _expr()
	var body := _block("while")
	return {"k": "While", "test": test, "body": body, "line": line}


func _for_stmt():
	var line: int = _next().line
	var nm := _expect("NAME", null, "for 後面要接一個變數名稱", "例如 for i in range(3):")
	_expect("KEYWORD", "in", "for 的寫法少了 in", "例如 for i in range(3):")
	var it = _expr()
	var body := _block("for")
	return {"k": "For", "var": nm.v, "iter": it, "body": body, "line": line}


# ---------------- 運算式 ----------------
func _expr():
	return _or()


func _or():
	var left = _and()
	while error.is_empty() and _is("KEYWORD", "or"):
		var ln: int = _next().line
		left = {"k": "BoolOp", "op": "or", "left": left, "right": _and(), "line": ln}
	return left


func _and():
	var left = _not()
	while error.is_empty() and _is("KEYWORD", "and"):
		var ln: int = _next().line
		left = {"k": "BoolOp", "op": "and", "left": left, "right": _not(), "line": ln}
	return left


func _not():
	if _is("KEYWORD", "not"):
		var ln: int = _next().line
		return {"k": "Not", "operand": _not(), "line": ln}
	return _compare()


func _compare():
	var left = _arith()
	var ops: Array = []
	var rights: Array = []
	while error.is_empty() and (_is("OP", "==") or _is("OP", "!=") or _is("OP", "<") or _is("OP", ">") or _is("OP", "<=") or _is("OP", ">=") or _is("KEYWORD", "in")):
		ops.append(_next().v)
		rights.append(_arith())
	if ops.is_empty():
		return left
	return {"k": "Compare", "left": left, "ops": ops, "rights": rights, "line": left.line if left else 0}


func _arith():
	var left = _term()
	while error.is_empty() and (_is("OP", "+") or _is("OP", "-")):
		var t := _next()
		left = {"k": "BinOp", "op": t.v, "left": left, "right": _term(), "line": t.line}
	return left


func _term():
	var left = _unary()
	while error.is_empty() and (_is("OP", "*") or _is("OP", "/") or _is("OP", "//") or _is("OP", "%")):
		var t := _next()
		left = {"k": "BinOp", "op": t.v, "left": left, "right": _unary(), "line": t.line}
	return left


func _unary():
	if _is("OP", "-") or _is("OP", "+"):
		var t := _next()
		return {"k": "Unary", "op": t.v, "operand": _unary(), "line": t.line}
	return _power()


func _power():
	var base = _postfix()
	if error.is_empty() and _is("OP", "**"):
		var t := _next()
		return {"k": "BinOp", "op": "**", "left": base, "right": _unary(), "line": t.line}
	return base


func _postfix():
	var node = _atom()
	while error.is_empty():
		if _is("OP", "("):
			var t := _next()
			var args: Array = []
			var kwargs := {}
			if not _is("OP", ")"):
				while true:
					if _is("NAME") and _is("OP", "=", 1):
						var kn: String = _next().v
						_next()
						kwargs[kn] = _expr()
					else:
						args.append(_expr())
					if not error.is_empty():
						return node
					if _accept("OP", ","):
						if _is("OP", ")"):
							break
						continue
					break
			if not _is("OP", ")"):
				var bad := _peek()
				if bad.t in ["STRING", "NAME", "NUMBER", "FSTRING"]:
					_fail("括號裡的兩個東西之間少了逗號「,」或加號「+」", "例如 print(\"a\", b) 或 print(\"a\" + b)。")
				else:
					_fail("少了右括號「)」", "每個「(」都要有對應的「)」。")
				return node
			_next()
			node = {"k": "Call", "func": node, "args": args, "kwargs": kwargs, "line": t.line}
		elif _is("OP", "."):
			_next()
			var nm := _expect("NAME", null, "「.」後面要接名稱")
			node = {"k": "Attribute", "obj": node, "attr": nm.v, "line": nm.line}
		elif _is("OP", "["):
			var t2 := _next()
			var idx = _expr()
			_expect("OP", "]", "少了右中括號「]」")
			node = {"k": "Index", "obj": node, "index": idx, "line": t2.line}
		else:
			break
	return node


func _atom():
	var t := _peek()
	match t.t:
		"NUMBER":
			_next()
			return {"k": "Const", "value": t.v, "line": t.line}
		"STRING":
			_next()
			var s: String = t.v
			# 相鄰字串自動串接，和 Python 一樣
			while _is("STRING"):
				s += _next().v
			return {"k": "Const", "value": s, "line": t.line, "is_str": true}
		"FSTRING":
			_next()
			return _fstring(t.v, t.line)
		"NAME":
			_next()
			return {"k": "Name", "id": t.v, "line": t.line}
		"KEYWORD":
			if t.v == "True" or t.v == "False":
				_next()
				return {"k": "Const", "value": t.v == "True", "line": t.line}
			if t.v == "None":
				_next()
				return {"k": "Const", "value": null, "line": t.line}
			_fail("「%s」不能放在這裡" % t.v, "「%s」是 Python 的保留字。" % t.v)
			return null
		"OP":
			if t.v == "(":
				_next()
				var e = _expr()
				_expect("OP", ")", "少了右括號「)」", "每個「(」都要有對應的「)」。")
				return e
			if t.v == "[":
				_next()
				var items: Array = []
				while not _is("OP", "]") and error.is_empty():
					items.append(_expr())
					if not _accept("OP", ","):
						break
				_expect("OP", "]", "少了右中括號「]」")
				return {"k": "List", "items": items, "line": t.line}
	if t.t == "NEWLINE" or t.t == "EOF":
		_fail("這一行還沒寫完", "可能少了右邊的值或右括號。")
	elif t.t == "INDENT":
		_fail("這一行多了縮排", "", "縮排錯誤")
	else:
		_fail("這裡不應該出現「%s」" % str(t.v), "請檢查這一行的寫法。")
	return null


func _fstring(raw: String, line: int) -> Dictionary:
	var parts: Array = []
	var i := 0
	var lit := ""
	while i < raw.length():
		var c := raw[i]
		if c == "{" and i + 1 < raw.length() and raw[i + 1] == "{":
			lit += "{"
			i += 2
			continue
		if c == "}" and i + 1 < raw.length() and raw[i + 1] == "}":
			lit += "}"
			i += 2
			continue
		if c == "{":
			var close := raw.find("}", i)
			if close < 0:
				_fail("f-string 的大括號「{」沒有關起來", "例如 f\"走了{a}步\"。")
				return {"k": "Const", "value": "", "line": line}
			if lit != "":
				parts.append({"k": "Const", "value": lit, "line": line})
				lit = ""
			var inner := raw.substr(i + 1, close - i - 1).strip_edges()
			if inner == "":
				_fail("f-string 的 {} 裡面是空的", "請在大括號裡放變數名稱，例如 {a}。")
				return {"k": "Const", "value": "", "line": line}
			var sub := PyParser.parse_expr(inner, line)
			if not sub.error.is_empty():
				if error.is_empty():
					error = sub.error
				p = toks.size() - 1
				return {"k": "Const", "value": "", "line": line}
			parts.append({"k": "FormattedValue", "value": sub.ast, "line": line, "src": inner})
			i = close + 1
			continue
		lit += c
		i += 1
	if lit != "":
		parts.append({"k": "Const", "value": lit, "line": line})
	return {"k": "JoinedStr", "parts": parts, "line": line}
