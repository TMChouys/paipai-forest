class_name PyLexer
extends RefCounted
## 簡化版 Python 斷詞器：產生含 INDENT / DEDENT 的 token 串列。
## 錯誤以中文訊息回報（行號從 1 開始）。

const KEYWORDS := ["if", "elif", "else", "while", "for", "in", "and", "or", "not",
	"True", "False", "None", "pass", "break", "continue", "import", "def", "return", "from", "as"]

## 全形 → 半形 對照（只在字串外檢查）
const FULLWIDTH := {
	"（": "(", "）": ")", "“": "\"", "”": "\"", "‘": "'", "’": "'",
	"，": ",", "：": ":", "＝": "=", "　": "空白", "＋": "+", "－": "-",
	"＊": "*", "／": "/", "＜": "<", "＞": ">", "［": "[", "］": "]",
	"｛": "{", "｝": "}", "；": ";", "＂": "\"", "＇": "'", "。": ".", "．": ".",
	"！": "!", "＃": "#",
}

const OPS3 := ["**=", "//="]
const OPS2 := ["==", "!=", "<=", ">=", "//", "**", "+=", "-=", "*=", "/=", "%="]
const OPS1 := "+-*/%<>=()[]{},:."

var src: String
var tokens: Array = []
var error: Dictionary = {}


static func tokenize(source: String) -> Dictionary:
	var lx := PyLexer.new()
	lx.src = source.replace("\r\n", "\n").replace("\r", "\n")
	lx._run()
	return {"tokens": lx.tokens, "error": lx.error}


func _err(line: int, col: int, msg: String, hint: String = "", kind: String = "語法錯誤") -> void:
	if error.is_empty():
		error = {"kind": kind, "line": line, "col": col, "message": msg, "hint": hint}


func _tok(t: String, v, line: int, col: int) -> void:
	tokens.append({"t": t, "v": v, "line": line, "col": col})


func _run() -> void:
	var lines := src.split("\n")
	var indent_stack: Array = [0]
	var paren_depth := 0
	for li in range(lines.size()):
		if not error.is_empty():
			return
		var line: String = lines[li]
		var ln := li + 1
		var i := 0
		var n := line.length()
		# --- 縮排（只在不在括號內時處理）---
		if paren_depth == 0:
			var width := 0
			while i < n and (line[i] == " " or line[i] == "\t" or line[i] == "　"):
				if line[i] == "　":
					_err(ln, i + 1, "第 %d 行開頭有全形空白「　」" % ln, "縮排請用半形空白鍵（建議 4 格）。")
					return
				width += 4 if line[i] == "\t" else 1
				i += 1
			var rest := line.substr(i).strip_edges()
			if rest == "" or rest.begins_with("#"):
				continue  # 空白行或註解行
			if width > indent_stack[-1]:
				indent_stack.append(width)
				_tok("INDENT", width, ln, 1)
			elif width < indent_stack[-1]:
				while width < indent_stack[-1]:
					indent_stack.pop_back()
					_tok("DEDENT", width, ln, 1)
				if width != indent_stack[-1]:
					_err(ln, 1, "第 %d 行的縮排對不齊" % ln, "同一層的程式要對齊，縮排的空白數要和上面一樣。", "縮排錯誤")
					return
		# --- 逐字 ---
		while i < n:
			var c := line[i]
			var col := i + 1
			if c == " " or c == "\t":
				i += 1
				continue
			if c == "#":
				break
			if FULLWIDTH.has(c):
				var half: String = FULLWIDTH[c]
				var show_half := "半形空白" if half == "空白" else "半形「%s」" % half
				_err(ln, col, "第 %d 行第 %d 個字是全形「%s」" % [ln, col, c],
					"程式的符號要用半形，請改成%s（輸入法切換到英數模式）。" % show_half, "全形符號")
				return
			# f-string / 字串
			var is_f := (c == "f" or c == "F") and i + 1 < n and (line[i + 1] == "\"" or line[i + 1] == "'")
			if c == "\"" or c == "'" or is_f:
				var q_start := i + 1 if is_f else i
				var q := line[q_start]
				var j := q_start + 1
				var buf := ""
				var closed := false
				while j < n:
					var ch := line[j]
					if ch == "\\" and j + 1 < n:
						var nx := line[j + 1]
						match nx:
							"n": buf += "\n"
							"t": buf += "\t"
							"\\": buf += "\\"
							"'": buf += "'"
							"\"": buf += "\""
							_: buf += "\\" + nx
						j += 2
						continue
					if ch == q:
						closed = true
						break
					buf += ch
					j += 1
				if not closed:
					var other_q := false
					for k in range(q_start + 1, n):
						if line[k] in ["“", "”", "‘", "’"]:
							other_q = true
					var hint := "字串要用同一種引號開頭和結尾，例如 \"你好\"。"
					if other_q:
						hint = "字串裡混到了全形引號「” 」，結尾請用半形的 %s。" % q
					_err(ln, col, "第 %d 行的字串少了結尾的引號 %s" % [ln, q], hint)
					return
				_tok("FSTRING" if is_f else "STRING", buf, ln, col)
				i = j + 1
				continue
			# 數字
			if c.is_valid_int():
				var j2 := i
				var has_dot := false
				while j2 < n and (line[j2].is_valid_int() or (line[j2] == "." and not has_dot and j2 + 1 < n and line[j2 + 1].is_valid_int())):
					if line[j2] == ".":
						has_dot = true
					j2 += 1
				var txt := line.substr(i, j2 - i)
				_tok("NUMBER", float(txt) if has_dot else int(txt), ln, col)
				i = j2
				continue
			# 名稱（允許中文識別字，和 Python 一樣）
			if _is_name_start(c):
				var j3 := i
				while j3 < n and (_is_name_start(line[j3]) or line[j3].is_valid_int()):
					j3 += 1
				var word := line.substr(i, j3 - i)
				_tok("KEYWORD" if word in KEYWORDS else "NAME", word, ln, col)
				i = j3
				continue
			# 運算子
			var matched := ""
			for op in OPS3:
				if line.substr(i, 3) == op:
					matched = op
			if matched == "":
				for op in OPS2:
					if line.substr(i, 2) == op:
						matched = op
			if matched == "" and OPS1.contains(c):
				matched = c
			if matched != "":
				if matched in ["(", "[", "{"]:
					paren_depth += 1
				elif matched in [")", "]", "}"]:
					paren_depth = max(0, paren_depth - 1)
				_tok("OP", matched, ln, col)
				i += matched.length()
				continue
			_err(ln, col, "第 %d 行有看不懂的符號「%s」" % [ln, c], "請檢查是不是打錯字，或文字忘了用引號包起來。")
			return
		if paren_depth == 0:
			_tok("NEWLINE", null, ln, n + 1)
	var last_line := lines.size()
	if paren_depth > 0 and error.is_empty():
		_err(last_line, 1, "括號沒有成對", "每個「(」都要有對應的「)」。")
		return
	while indent_stack.size() > 1:
		indent_stack.pop_back()
		_tok("DEDENT", 0, last_line, 1)
	_tok("EOF", null, last_line, 1)


static func _is_name_start(c: String) -> bool:
	if c == "_":
		return true
	var code := c.unicode_at(0)
	if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return true
	# 中日韓文字（Python 也允許中文變數名）
	return code >= 0x4E00 and code <= 0x9FFF
