class_name LessonBook
extends Control
## 慢慢館長的課（在圖書館點館長打開）。一課只教一個概念，照課本章節、依知識地圖（心智圖）分門別類。
## 左頁：知識地圖的分類（A～K）→ 這一類的概念；右頁：五個步驟
##   ① 這一課要學什麼 → ② 你知道嗎？（先提問）→ ③ 講解（範例＋執行結果）→ ④ 選擇練習（對答案）→ ⑤ 相關任務
## 課文在 data/curriculum/lessons.json（tools/curriculum/gen_lessons.py 產生）。

signal lesson_done(concept_id: String)
signal closed

const LESSON_PATH := "res://data/curriculum/lessons.json"
const STEPS := ["① 要學什麼", "② 你知道嗎？", "③ 講解", "④ 選擇練習", "⑤ 相關任務"]
const CODE_BG := Color("2f3a33")
const CODE_INK := Color("f4efe2")

var kmap: Dictionary = {}
var lessons: Dictionary = {}
var concepts: Dictionary = {}      # id -> concept（知識地圖＋補上的演算法概念）
var order: Array = []              # 照分類排好的概念 id
var done: Dictionary = {}          # 選擇練習答對的概念
var area_id := "A"
var concept_id := "print"
var step := 0
var _asked := false                # ② 已經回答「知道／不確定」
var _quiz_pick := -1               # ④ 選了哪一個

var index_box: VBoxContainer
var title_l: Label
var chap_l: Label
var step_row: HBoxContainer
var body: VBoxContainer
var body_scroll: ScrollContainer
var prev_b: Button
var next_b: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	kmap = QuestBook.load_map()
	var f := FileAccess.open(LESSON_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else {}
	if d is Dictionary:
		lessons = d.get("lessons", {})
		for c in kmap.get("concepts", []) + d.get("extra_concepts", []):
			concepts[c.id] = c
	for a in kmap.get("areas", []):
		for c in concepts.values():
			if c.area == a.id and lessons.has(c.id):
				order.append(c.id)
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.12, 0.05, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var book := PanelContainer.new()
	book.anchor_left = 0.5
	book.anchor_right = 0.5
	book.anchor_top = 0.5
	book.anchor_bottom = 0.5
	book.offset_left = -610
	book.offset_right = 610
	book.offset_top = -340
	book.offset_bottom = 340
	var bst := UIKit.panel_style(Color("5b4370"), 22, UIKit.INK, 3)  # 紫色書皮（館長的披風色）
	bst.set_content_margin_all(12)
	book.add_theme_stylebox_override("panel", bst)
	add_child(book)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	book.add_child(pages)
	var pst := UIKit.panel_style(Color("fff8ec"), 14, UIKit.INK, 2)
	pst.shadow_size = 0

	# ---- 左頁：知識地圖分類 ----
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 290
	left.add_theme_stylebox_override("panel", pst)
	pages.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	var t := UIKit.label("慢慢館長的課", 24)
	t.add_theme_font_override("font", UIKit.font_bold())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(t)
	var sub := UIKit.label("一次只學一個概念・照課本的章節", 13, Color("8a6a50"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	index_box = VBoxContainer.new()
	index_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	index_box.add_theme_constant_override("separation", 3)
	sc.add_child(index_box)

	# ---- 右頁：一課的五個步驟 ----
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", pst)
	pages.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	var rh := HBoxContainer.new()
	rv.add_child(rh)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	rh.add_child(tv)
	title_l = UIKit.label("", 24)
	title_l.add_theme_font_override("font", UIKit.font_bold())
	tv.add_child(title_l)
	chap_l = UIKit.label("", 14, Color("8a6a50"))
	tv.add_child(chap_l)
	var x := UIKit.focusable(UIKit.button("×", close, "關閉（Esc）"))
	x.custom_minimum_size = Vector2(36, 36)
	x.add_theme_font_size_override("font_size", 20)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rh.add_child(x)
	step_row = HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 6)
	rv.add_child(step_row)
	body_scroll = ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(body_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body_scroll.add_child(body)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	rv.add_child(nav)
	prev_b = UIKit.focusable(UIKit.button("← 上一步", func(): _go(step - 1)))
	nav.add_child(prev_b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	next_b = UIKit.primary(UIKit.focusable(UIKit.button("下一步 →", _next)))
	nav.add_child(next_b)


## done_list：之前答對過的概念
func open(done_list: Array = [], cid: String = "") -> void:
	done.clear()
	for c in done_list:
		done[c] = true
	if cid == "" or not lessons.has(cid):
		cid = concept_id
		for c in order:   # 預設打開第一個還沒學會的
			if not done.has(c):
				cid = c
				break
	visible = true
	show_concept(cid)


func close() -> void:
	visible = false
	closed.emit()


func show_concept(cid: String) -> void:
	if not lessons.has(cid):
		return
	concept_id = cid
	area_id = concepts[cid].area
	step = -1
	_fill_index()
	var c: Dictionary = concepts[cid]
	var les: Dictionary = lessons[cid]
	title_l.text = c.name
	chap_l.text = "%s　｜　課本 %s　｜　知識地圖 %s %s" % [les.chapter, les.ch, area_id, _area(area_id).get("name", "")]
	_go(0)


func _area(aid: String) -> Dictionary:
	for a in kmap.get("areas", []):
		if a.id == aid:
			return a
	return {}


func _fill_index() -> void:
	for n in index_box.get_children():
		n.queue_free()
	for a in kmap.get("areas", []):
		var cs := order.filter(func(id): return concepts[id].area == a.id)
		if cs.is_empty():
			continue
		var n_done := cs.filter(func(id): return done.has(id)).size()
		var b := UIKit.focusable(UIKit.button("%s　%s　%d/%d" % [a.id, a.name, n_done, cs.size()], _open_area.bind(a.id), a.summary))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var st := UIKit.panel_style(Color(a.color).lightened(0.5), 10, UIKit.INK, 3 if a.id == area_id else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		index_box.add_child(b)
		if a.id != area_id:
			continue
		for id in cs:   # 展開這一類的概念
			var cb := UIKit.focusable(UIKit.button(("✓ " if done.has(id) else "・ ") + concepts[id].name, show_concept.bind(id), concepts[id].get("summary", "")))
			cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cb.add_theme_font_size_override("font_size", 15)
			var cst := UIKit.panel_style(Color("fffdf6") if id != concept_id else Color(a.color).lightened(0.3), 8, UIKit.INK if id == concept_id else Color("d8c3a5"), 2 if id == concept_id else 1)
			cst.shadow_size = 0
			cst.content_margin_left = 18
			cb.add_theme_stylebox_override("normal", cst)
			cb.add_theme_stylebox_override("hover", cst)
			if done.has(id):
				cb.add_theme_color_override("font_color", UIKit.TEXT_GREEN)
			index_box.add_child(cb)


func _open_area(aid: String) -> void:
	for id in order:
		if concepts[id].area == aid:
			show_concept(id)
			return


func _next() -> void:
	if step < STEPS.size() - 1:
		_go(step + 1)
		return
	var i := order.find(concept_id)   # 最後一步：下一課
	if i >= 0 and i + 1 < order.size():
		show_concept(order[i + 1])


func _go(s: int) -> void:
	var old := step
	step = clampi(s, 0, STEPS.size() - 1)
	if step == 1 and old != 1:
		_asked = false
	if step == 3:
		_quiz_pick = -1
	for n in step_row.get_children():
		n.queue_free()
	for i in STEPS.size():
		var b := UIKit.focusable(UIKit.button(STEPS[i], _go.bind(i)))
		b.add_theme_font_size_override("font_size", 15)
		var st := UIKit.panel_style(Color("e9d9f2") if i == step else Color("fffdf6"), 10, UIKit.INK, 2 if i == step else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		step_row.add_child(b)
	prev_b.disabled = step == 0
	var i_c := order.find(concept_id)
	next_b.text = "下一步 →" if step < STEPS.size() - 1 else ("下一課 →" if i_c + 1 < order.size() else "全部上完了！")
	next_b.disabled = step == STEPS.size() - 1 and i_c + 1 >= order.size()
	for n in body.get_children():
		n.queue_free()
	body_scroll.scroll_vertical = 0
	var les: Dictionary = lessons[concept_id]
	match step:
		0: _step_goal(les)
		1: _step_ask(les)
		2: _step_explain(les)
		3: _step_quiz(les)
		4: _step_tasks(les)


# ---------------- 畫面小零件 ----------------
func _text(t: String, size: int = 17, color: Color = UIKit.INK) -> Label:
	var l := UIKit.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _card(bg: Color, border: Color = Color("d8c3a5")) -> VBoxContainer:
	var p := PanelContainer.new()
	var st := UIKit.panel_style(bg, 12, border, 2)
	st.shadow_size = 0
	st.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", st)
	body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


func _code(t: String, title: String, bg: Color = CODE_BG, ink: Color = CODE_INK) -> void:
	body.add_child(_text(title, 15, Color("8a6a50")))
	var p := PanelContainer.new()
	var st := UIKit.panel_style(bg, 10, UIKit.INK, 1)
	st.shadow_size = 0
	st.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", st)
	var l := UIKit.label(t, 17, ink)
	l.add_theme_font_override("font", UIKit.mono())
	p.add_child(l)
	body.add_child(p)


func _turtle(t: String) -> void:
	var v := _card(Color("f1e8f7"), Color("b9a1cf"))
	v.add_child(_text("慢慢館長：", 14, Color("6b4f86")))
	v.add_child(_text(t, 17))


# ---------------- 五個步驟 ----------------
func _step_goal(les: Dictionary) -> void:
	var v := _card(Color("fff3d6"), Color("e3c27a"))
	v.add_child(_text("這一課要學", 15, Color("8f5f12")))
	var g := _text(les.goal, 22)
	g.add_theme_font_override("font", UIKit.font_bold())
	v.add_child(g)
	body.add_child(_text("課本：%s　%s" % [les.chapter, les.ch], 15, UIKit.TEXT_MUTED))
	var c: Dictionary = concepts[concept_id]
	var pre: Array = c.get("prereqs", [])
	if not pre.is_empty():
		var names := []
		for p in pre:
			names.append(("✓" if done.has(p) else "○") + (concepts[p].name if concepts.has(p) else p))
		body.add_child(_text("先學過會比較好懂：" + "、".join(names), 15, UIKit.TEXT_MUTED))
	if les.get("note", "") != "":
		body.add_child(_text("※ " + les.note, 15, UIKit.TEXT_WARN))
	_turtle("慢慢來，比較快。我們一次只學一個概念。準備好了，就按「下一步」。")


func _step_ask(les: Dictionary) -> void:
	var v := _card(Color("eef6ff"), Color("9cc3e6"))
	v.add_child(_text("你知道嗎？", 15, UIKit.TEXT_INFO))
	var q := _text(les.ask, 22)
	q.add_theme_font_override("font", UIKit.font_bold())
	v.add_child(q)
	if not _asked:
		body.add_child(_text("先想一想，再選一個：", 15, UIKit.TEXT_MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		for k in ["我知道！", "不太確定"]:
			row.add_child(UIKit.focusable(UIKit.button(k, func():
				_asked = true
				_go(1))))
	else:
		_turtle(les.ask_answer + "\n接下來，我們慢慢講清楚。")


func _step_explain(les: Dictionary) -> void:
	var v := _card(Color("fffdf6"))
	for i in les.explain.size():
		v.add_child(_text("%d. %s" % [i + 1, les.explain[i]], 17))
	_code(les.code, "範例程式")
	var inputs: Array = les.get("inputs", [])
	_code(les.output, "執行結果" + ("（假裝輸入了：%s）" % "、".join(inputs) if not inputs.is_empty() else ""), Color("fffaf0"), UIKit.INK)
	_turtle("看完範例，先猜猜看：如果把裡面的數字或文字改掉，結果會變成什麼？")


func _step_quiz(les: Dictionary) -> void:
	var qz: Dictionary = les.quiz
	var lines: PackedStringArray = String(qz.q).split("\n")
	var v := _card(Color("fffdf6"))
	v.add_child(_text("選擇練習", 15, UIKit.TEXT_INFO))
	var q := _text(lines[0], 20)
	q.add_theme_font_override("font", UIKit.font_bold())
	v.add_child(q)
	if lines.size() > 1:   # 題目裡的程式碼
		var code := UIKit.label("\n".join(lines.slice(1)), 17, CODE_INK)
		code.add_theme_font_override("font", UIKit.mono())
		var p := PanelContainer.new()
		var st := UIKit.panel_style(CODE_BG, 10, UIKit.INK, 1)
		st.shadow_size = 0
		st.set_content_margin_all(10)
		p.add_theme_stylebox_override("panel", st)
		p.add_child(code)
		v.add_child(p)
	var letters := ["A", "B", "C", "D"]
	for i in qz.options.size():
		var b := UIKit.focusable(UIKit.button("%s　%s" % [letters[i], qz.options[i]], _pick.bind(i)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UIKit.mono())
		if _quiz_pick >= 0:
			var right: bool = i == int(qz.answer)
			var col := Color("d8f0d0") if right else (Color("f6d3cf") if i == _quiz_pick else Color("fffdf6"))
			var st2 := UIKit.panel_style(col, 10, UIKit.INK, 2 if right or i == _quiz_pick else 1)
			st2.shadow_size = 0
			b.add_theme_stylebox_override("normal", st2)
			b.add_theme_stylebox_override("disabled", st2)
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", UIKit.INK)
			b.text += "　✓ 正確答案" if right else ("　✗" if i == _quiz_pick else "")
		body.add_child(b)
	if _quiz_pick >= 0:
		var ok := _quiz_pick == int(qz.answer)
		var fb := _card(Color("eaf6e4") if ok else Color("fdeceb"), UIKit.GREEN if ok else UIKit.RED)
		fb.add_child(_text("答對了！" if ok else "不對喔，正確答案是 %s。" % letters[int(qz.answer)], 20, UIKit.TEXT_GREEN if ok else UIKit.TEXT_RED))
		fb.add_child(_text(qz.why, 17))
		if not ok:
			var again := UIKit.focusable(UIKit.button("再做一次", func(): _go(3)))
			body.add_child(again)


func _pick(i: int) -> void:
	_quiz_pick = i
	if i == int(lessons[concept_id].quiz.answer) and not done.has(concept_id):
		done[concept_id] = true
		lesson_done.emit(concept_id)
		_fill_index()
	for n in body.get_children():
		n.queue_free()
	_step_quiz(lessons[concept_id])
	await get_tree().process_frame
	body_scroll.scroll_vertical = 10000   # 捲到下面看解答


func _step_tasks(les: Dictionary) -> void:
	var ids: Array = les.get("tasks") if les.get("tasks") != null else []
	var ts: Array = kmap.get("tasks", []).filter(func(t): return concept_id in t.concepts or t.id in ids)
	ts.sort_custom(func(a, b):
		if a.compound != b.compound:
			return not a.compound
		return int(a.difficulty) < int(b.difficulty))
	_turtle("學會了「%s」，派派森林裡有這些委託會用到它。" % concepts[concept_id].name if not ts.is_empty() else "這個概念的委託還在準備中。")
	for t in ts:
		var v := _card(Color("fffdf6"))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		top.add_child(QuestBook._tag("複合知識" if t.compound else "單一概念", Color("f4a8a0") if t.compound else Color("cfe3f5")))
		var tl := UIKit.label(t.title, 18)
		tl.add_theme_font_override("font", UIKit.font_bold())
		top.add_child(tl)
		top.add_child(UIKit.label("★".repeat(int(t.difficulty)) + "☆".repeat(5 - int(t.difficulty)), 15, UIKit.TEXT_WARN))
		var place: String = kmap.get("places", {}).get(t.place, t.place)
		var npc: String = kmap.get("npcs", {}).get(t.npc, t.npc)
		var status: String = kmap.get("status_names", {}).get(t.status, t.status)
		v.add_child(_text("%s・%s的委託　｜　%s" % [place, npc, status], 14, Color("8a6a50")))
		v.add_child(_text(t.story, 16))
