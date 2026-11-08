class_name LessonBook
extends Control
## 認識派派森林的世界：慢慢館長說故事（認知）＋派派兔帶選擇題小測驗（形成性評量）。
## 點派派兔：「準備好一起認識派派森林的世界了嗎？我們去找慢慢館長聽故事吧！」→ 走進圖書館，館長打開這本書。
## 一課只教一個概念，照課本章節、依知識地圖（心智圖）分門別類。
## 左頁：知識地圖的分類（A～K）→ 這一類的概念；右頁：五個步驟，上面的小舞台由三個角色演出來
##   ① 要知道什麼事？（先提問）→ ② 為什麼？ → ③ 怎麼做？（範例＋執行結果）
##   → ④ 小測驗（一題一題：作答 → 正解或糾正錯誤＋詳解 → 鼓勵 → 下一題；全部答對才算學會）→ ⑤ 去冒險（派派狼的相關任務）
## 課文在 data/curriculum/lessons.json（tools/curriculum/gen_lessons.py 產生）。
## 班級版另外有 data/class/class_lessons.json（gen_class_lessons.py 產生，不進 git、公開版不匯出）：
##   三本教材的簡報文字與習題依知識點整合，多出「課本整理」「習題」兩頁，還有知識地圖沒有的分類（P、Q）。

signal lesson_done(concept_id: String)
signal closed

const LESSON_PATH := "res://data/curriculum/lessons.json"
const CLASS_PATH := "res://data/class/class_lessons.json"
const STEPS := ["① 要知道什麼事？", "② 為什麼？", "③ 怎麼做？", "④ 小測驗", "⑤ 去冒險"]
const CHEER_RIGHT := ["好厲害！", "派派鼠也在幫你拍手！", "就是這樣！", "你越來越懂派派森林了！", "完全正確！"]
const CHEER_WRONG := ["沒關係，錯了才知道哪裡要注意。", "差一點點！看懂原因就學會了。", "慢慢來，比較快。", "下一題一定可以！"]
const CLASS_STEPS := ["📖 課本整理", "✎ 習題"]
const CODE_BG := Color("2f3a33")
const CODE_INK := Color("f4efe2")

var kmap: Dictionary = {}
var lessons: Dictionary = {}
var class_content: Dictionary = {} # 班級版：id -> {slides, exercises}
var areas: Array = []              # 知識地圖的分類（班級版多 P、Q）
var steps: Array = []              # 這一課有哪些步驟：0～4 是五個步驟，10 課本整理、11 習題
var _shown: Dictionary = {}        # 習題「看答案」打開了哪幾題
var concepts: Dictionary = {}      # id -> concept（知識地圖＋補上的演算法概念）
var order: Array = []              # 照分類排好的概念 id
var done: Dictionary = {}          # 選擇練習答對的概念
var area_id := "A"
var concept_id := "print"
var step := 0
var _asked := false                # ② 已經回答「知道／不確定」
var _quiz_pick := -1               # ④ 這一題選了哪一個
var _qi := 0                       # ④ 第幾題
var _right: Dictionary = {}        # ④ 這一課答對過的題目
var stage: LessonStage             # 小舞台：三個角色演出來
var quiz_mode := true              # true：派派兔帶來（故事＋小測驗）；false：點慢慢館長（只有知識地圖和知識說明，沒有測驗）
var book_style: StyleBoxFlat
var title_book: Label
var sub_book: Label

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
	areas = kmap.get("areas", []).duplicate()
	if FileAccess.file_exists(CLASS_PATH):
		var cf := FileAccess.open(CLASS_PATH, FileAccess.READ)
		var cd = JSON.parse_string(cf.get_as_text()) if cf else null
		if cd is Dictionary:
			class_content = cd.get("content", {})
			areas += cd.get("areas", [])
			for t in cd.get("topics", []):
				concepts[t.id] = t
	areas.sort_custom(func(a, b): return int(a.order) < int(b.order))
	for a in areas:
		for c in concepts.values():
			if c.area == a.id and _has(c.id):
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
	var bst := UIKit.panel_style(Color("c27a6e"), 22, UIKit.INK, 3)  # 紅蘿蔔色書皮（派派兔）；館長的書是紫色
	book_style = bst
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
	var t := UIKit.label("認識派派森林的世界", 24)
	title_book = t
	t.add_theme_font_override("font", UIKit.font_bold())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(t)
	var sub := UIKit.label("慢慢館長說故事・派派兔帶小測驗", 13, Color("8a6a50"))
	sub_book = sub
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
	stage = LessonStage.new()
	rv.add_child(stage)
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


func _has(cid: String) -> bool:
	return lessons.has(cid) or class_content.has(cid)


## done_list：之前答對過的概念
## quiz：true＝派派兔帶來聽故事＋小測驗；false＝點慢慢館長，只看知識地圖和知識說明
func open(done_list: Array = [], cid: String = "", quiz: bool = true) -> void:
	quiz_mode = quiz
	book_style.bg_color = Color("c27a6e") if quiz else Color("5b4370")
	title_book.text = "認識派派森林的世界" if quiz else "慢慢館長的知識地圖"
	sub_book.text = "慢慢館長說故事・派派兔帶小測驗" if quiz else "詳細的知識說明・照課本章節（小測驗找派派兔）"
	done.clear()
	for c in done_list:
		done[c] = true
	if cid == "" or not _has(cid):
		cid = concept_id
		for c in order:   # 預設打開第一個還沒學會、有故事的課
			if not done.has(c) and lessons.has(c):
				cid = c
				break
	visible = true
	show_concept(cid)


func close() -> void:
	stage.stop()
	visible = false
	closed.emit()


func show_concept(cid: String) -> void:
	if not _has(cid):
		return
	concept_id = cid
	area_id = concepts[cid].area
	step = -1
	_qi = 0
	_right.clear()
	_shown.clear()
	steps = []
	if lessons.has(cid):
		steps.append_array(range(STEPS.size()) if quiz_mode else [0, 1, 2])
	if class_content.has(cid):
		var cc: Dictionary = class_content[cid]
		if not cc.get("slides", []).is_empty():
			steps.append(10)
		if quiz_mode and not cc.get("exercises", []).is_empty():
			steps.append(11)
	_fill_index()
	var c: Dictionary = concepts[cid]
	title_l.text = c.name
	if lessons.has(cid):
		var les: Dictionary = lessons[cid]
		chap_l.text = "%s　｜　課本 %s　｜　知識地圖 %s %s" % [les.chapter, les.ch, area_id, _area(area_id).get("name", "")]
	else:
		chap_l.text = "%s　｜　知識地圖 %s %s" % [c.get("summary", ""), area_id, _area(area_id).get("name", "")]
	_go(0)


func _area(aid: String) -> Dictionary:
	for a in areas:
		if a.id == aid:
			return a
	return {}


func _fill_index() -> void:
	for n in index_box.get_children():
		n.queue_free()
	for a in areas:
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
	if step < steps.size() - 1:
		_go(step + 1)
		return
	var i := order.find(concept_id)   # 最後一步：下一課
	if i >= 0 and i + 1 < order.size():
		show_concept(order[i + 1])


func _go(s: int) -> void:
	var old := step
	step = clampi(s, 0, steps.size() - 1)
	var kind: int = steps[step]
	if kind == 0 and old != step:
		_asked = false
	if kind == 3 and old != step:
		_quiz_pick = -1
	stage.visible = kind in [0, 1, 3]
	stage.stop()
	for n in step_row.get_children():
		n.queue_free()
	for i in steps.size():
		var k: int = steps[i]
		var b := UIKit.focusable(UIKit.button(STEPS[k] if k < 10 else CLASS_STEPS[k - 10], _go.bind(i)))
		b.add_theme_font_size_override("font_size", 15)
		var st := UIKit.panel_style(Color("e9d9f2") if i == step else Color("fffdf6"), 10, UIKit.INK, 2 if i == step else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		step_row.add_child(b)
	prev_b.disabled = step == 0
	var i_c := order.find(concept_id)
	next_b.text = "下一步 →" if step < steps.size() - 1 else ("下一課 →" if i_c + 1 < order.size() else "全部上完了！")
	next_b.disabled = step == steps.size() - 1 and i_c + 1 >= order.size()
	for n in body.get_children():
		n.queue_free()
	body_scroll.scroll_vertical = 0
	var les: Dictionary = lessons.get(concept_id, {})
	match kind:
		0: _step_goal(les)
		1: _step_why(les)
		2: _step_explain(les)
		3: _step_quiz(les)
		4: _step_tasks(les)
		10: _step_slides()
		11: _step_exercises()


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


func _rabbit(t: String) -> void:
	var v := _card(Color("fdecea"), Color("e3a59c"))
	v.add_child(_text("派派兔：", 14, Color("a0544a")))
	v.add_child(_text(t, 17))


func _wolf(t: String) -> void:
	var v := _card(Color("e9eef6"), Color("98a9c4"))
	v.add_child(_text("派派狼：", 14, Color("4a5a78")))
	v.add_child(_text(t, 17))


func _turtle(t: String) -> void:
	var v := _card(Color("f1e8f7"), Color("b9a1cf"))
	v.add_child(_text("慢慢館長：", 14, Color("6b4f86")))
	v.add_child(_text(t, 17))


# ---------------- 五個步驟 ----------------
func _step_goal(les: Dictionary) -> void:
	var v := _card(Color("fff3d6"), Color("e3c27a"))
	v.add_child(_text("要知道什麼事？", 15, Color("8f5f12")))
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
		body.add_child(_text("先認識過會比較好懂：" + "、".join(names), 15, UIKit.TEXT_MUTED))
	if les.get("note", "") != "":
		body.add_child(_text("※ " + les.note, 15, UIKit.TEXT_WARN))
	var q := _card(Color("eef6ff"), Color("9cc3e6"))
	q.add_child(_text("你知道嗎？", 15, UIKit.TEXT_INFO))
	var qt := _text(les.ask, 20)
	qt.add_theme_font_override("font", UIKit.font_bold())
	q.add_child(qt)
	if not _asked:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		for k in ["我知道！", "不太確定"]:
			row.add_child(UIKit.focusable(UIKit.button(k, func():
				_asked = true
				_go(step))))
		stage.play([["rabbit", "館長，我們來聽故事了！", "hop"], ["turtle", les.ask]] if quiz_mode else [["turtle", les.ask]])
	else:
		_turtle(les.ask_answer + "\n接下來說說：為什麼要知道這件事？")
		stage.play([["turtle", les.ask_answer]])


func _step_why(les: Dictionary) -> void:
	var why: String = les.get("why", "")
	if why == "":
		why = les.ask_answer
	var v := _card(Color("fff3d6"), Color("e3c27a"))
	v.add_child(_text("為什麼？", 15, Color("8f5f12")))
	v.add_child(_text(why, 19))
	_turtle("知道了「為什麼」，下一步看看「怎麼做」。")
	stage.play([["wolf", "館長，學這個要做什麼？"], ["turtle", why]])


func _step_explain(les: Dictionary) -> void:
	var v := _card(Color("fffdf6"))
	for i in les.explain.size():
		v.add_child(_text("%d. %s" % [i + 1, les.explain[i]], 17))
	_code(les.code, "範例程式")
	var inputs: Array = les.get("inputs", [])
	_code(les.output, "執行結果" + ("（假裝輸入了：%s）" % "、".join(inputs) if not inputs.is_empty() else ""), Color("fffaf0"), UIKit.INK)
	_turtle("看完範例，先猜猜看：如果把裡面的數字或文字改掉，結果會變成什麼？" + ("猜好了，派派兔會帶你做小測驗。" if quiz_mode else "想試試看自己懂了沒有，就去找派派兔做小測驗吧。"))


## 這一課的全部題目：原本那一題＋派派兔多出的題目
func _questions(les: Dictionary) -> Array:
	return [les.quiz] + les.get("quiz_more", [])


func _step_quiz(les: Dictionary) -> void:
	var qs := _questions(les)
	_qi = clampi(_qi, 0, qs.size() - 1)
	var qz: Dictionary = qs[_qi]
	var lines: PackedStringArray = String(qz.q).split("\n")
	var v := _card(Color("fffdf6"))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UIKit.label("小測驗　第 %d／%d 題　派派兔問派派鼠：" % [_qi + 1, qs.size()], 15, UIKit.TEXT_INFO))
	var dots := ""
	for i in qs.size():
		dots += "●" if _right.has(i) else ("◉" if i == _qi else "○")
	top.add_child(UIKit.label(dots, 15, UIKit.TEXT_GREEN))
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
	if _qi == 0 and _quiz_pick < 0 and _right.is_empty():
		_rabbit("剛剛館長說的故事，換我來問派派鼠囉！你幫派派鼠選一個答案。一題一題來，答錯也沒關係。")
	var letters := ["A", "B", "C", "D"]
	var ans := int(qz.answer)
	for i in qz.options.size():
		var b := UIKit.focusable(UIKit.button("%s　%s" % [letters[i], qz.options[i]], _pick.bind(i)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UIKit.mono())
		if _quiz_pick >= 0:
			var ok_i: bool = i == ans and _quiz_pick == ans
			var col := Color("d8f0d0") if ok_i else (Color("f6d3cf") if i == _quiz_pick else Color("fffdf6"))
			var st2 := UIKit.panel_style(col, 10, UIKit.INK, 2 if i == _quiz_pick else 1)
			st2.shadow_size = 0
			b.add_theme_stylebox_override("normal", st2)
			b.add_theme_stylebox_override("disabled", st2)
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", UIKit.INK)
			if i == _quiz_pick:
				b.text += "　✓" if ok_i else "　✗"
		body.add_child(b)
	if _quiz_pick < 0:
		var skit: Array = qz.get("skit", [])
		# 題目情境演出來 → 派派兔問派派鼠 → 派派鼠想一想（玩家幫派派鼠選）
		stage.play(skit + [["rabbit", "派派鼠，" + lines[0]], ["gopher", "……", "think"]])
		return
	var ok := _quiz_pick == ans
	var pool: Array = CHEER_RIGHT if ok else CHEER_WRONG
	var cheer: String = pool[(_qi * 3 + _quiz_pick) % pool.size()]
	var fb := _card(Color("eaf6e4") if ok else Color("fdeceb"), UIKit.GREEN if ok else UIKit.RED)
	if ok:
		fb.add_child(_text("答對了！" + cheer, 20, UIKit.TEXT_GREEN))
		fb.add_child(_text("詳解：" + String(qz.why), 17))
	else:
		var wrong: Array = qz.get("wrong", [])
		var fix: String = wrong[_quiz_pick] if _quiz_pick < wrong.size() else ""
		fb.add_child(_text("再想想看！你選的是 %s。" % letters[_quiz_pick], 20, UIKit.TEXT_RED))
		fb.add_child(_text("哪裡不對：" + (fix if fix != "" else "這個答案不對喔。"), 17))
		fb.add_child(_text("詳解：" + String(qz.why), 17))
		fb.add_child(_text(cheer, 16, UIKit.TEXT_WARN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	if not ok:
		row.add_child(UIKit.focusable(UIKit.button("再試一次", func():
				_quiz_pick = -1
				_go(step))))
	var left: Array = []
	for i in qs.size():
		if not _right.has(i):
			left.append(i)
	if left.is_empty():
		var all_l := _text("這一課的 %d 題全部答對了！學會「%s」了。" % [qs.size(), concepts[concept_id].name], 18, UIKit.TEXT_GREEN)
		all_l.add_theme_font_override("font", UIKit.font_bold())
		body.add_child(all_l)
		row.add_child(UIKit.primary(UIKit.focusable(UIKit.button("去冒險 →", func(): _go(step + 1)))))
	else:
		var nxt := -1
		for i in left:   # 下一題：往後找還沒答對的；後面都答對了，就回到前面還沒答對的
			if i > _qi:
				nxt = i
				break
		if nxt < 0:
			for i in left:
				if i != _qi:
					nxt = i
					break
		if nxt >= 0:
			row.add_child(UIKit.primary(UIKit.focusable(UIKit.button("下一題 →" if nxt > _qi else "回去做還沒答對的題目 →", func():
					_qi = nxt
					_quiz_pick = -1
					_go(step)))))
	# 演出來：派派鼠說出選的答案 → 答對：程式跑出來的結果＋派派兔鼓勵；答錯：派派兔糾正＋鼓勵
	var said := ["gopher", "（選 %s）%s" % [letters[_quiz_pick], qz.options[_quiz_pick]], "think"]
	if ok:
		var act: Array = qz.get("act", [])
		stage.play([said] + act + [["rabbit", cheer, "happy"]])
	else:
		var wl: Array = qz.get("wrong", [])
		var fix2: String = wl[_quiz_pick] if _quiz_pick < wl.size() else ""
		stage.play([said, ["rabbit", "嗯……不對喔。" + fix2], ["rabbit", cheer]])


func _pick(i: int) -> void:
	var qs := _questions(lessons[concept_id])
	_quiz_pick = i
	if i == int(qs[_qi].answer):
		_right[_qi] = true
		if _right.size() >= qs.size() and not done.has(concept_id):
			done[concept_id] = true
			lesson_done.emit(concept_id)
			_fill_index()
	_go(step)
	await get_tree().process_frame
	body_scroll.scroll_vertical = 10000   # 捲到下面看詳解


func _step_tasks(les: Dictionary) -> void:
	var ids: Array = les.get("tasks") if les.get("tasks") != null else []
	var ts: Array = kmap.get("tasks", []).filter(func(t): return concept_id in t.concepts or t.id in ids)
	ts.sort_custom(func(a, b):
		if a.compound != b.compound:
			return not a.compound
		return int(a.difficulty) < int(b.difficulty))
	_wolf("學會了「%s」？準備好一起冒險了嗎？這些任務會用到它，來找我就出發！" % concepts[concept_id].name if not ts.is_empty() else "這件事的冒險還在準備中，先去認識下一件事吧！")
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


# ---------------- 班級版：課本整理、習題 ----------------
static var _re_cjk := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
static var _re_code := RegEx.create_from_string("[=()\\[\\]:#]|^\\s*(for|if|while|def|import|from|print|else|elif|return)\\b")


static func _is_code(l: String) -> bool:
	if _re_cjk.search(l) != null and not l.contains("print(") and not l.contains("#"):
		return false
	return _re_code.search(l) != null


func _mono_box(parent: Control, t: String) -> void:
	var c := UIKit.label(t, 15, CODE_INK)
	c.add_theme_font_override("font", UIKit.mono())
	var p := PanelContainer.new()
	var st := UIKit.panel_style(CODE_BG, 8, UIKit.INK, 1)
	st.shadow_size = 0
	st.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", st)
	p.add_child(c)
	parent.add_child(p)


func _lines_card(lines: Array) -> VBoxContainer:
	var v := _card(Color("fffdf6"))
	var buf: Array = []
	for l in lines + [""]:
		if l != "" and _is_code(l):
			buf.append(l)
			continue
		if not buf.is_empty():
			_mono_box(v, "\n".join(buf))
			buf.clear()
		if l != "":
			v.add_child(_text(l, 16))
	return v


func _step_slides() -> void:
	var sl: Array = class_content[concept_id].slides
	_turtle("這是三本課本的簡報裡講「%s」的內容，一共 %d 張。每一張都寫了出自哪一本、第幾章、第幾張。" % [concepts[concept_id].name, sl.size()])
	for s in sl:
		var v := _lines_card(s.lines)
		var src := _text("出處：%s｜%s" % [s.src, s.sec if s.sec != "" else "章首"], 13, Color("6b4f86"))
		v.add_child(src)
		v.move_child(src, 0)
		for ex in s.get("code", []):
			v.add_child(_text("本書範例 " + ex.file, 14, Color("8a6a50")))
			_mono_box(v, ex.code)


func _step_exercises() -> void:
	var ex: Array = class_content[concept_id].exercises
	_turtle("課本裡跟「%s」有關的習題，一共 %d 題。先自己想，再按「看答案」。" % [concepts[concept_id].name, ex.size()])
	for i in ex.size():
		var e: Dictionary = ex[i]
		var v := _card(Color("fffdf6"))
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		v.add_child(top)
		top.add_child(QuestBook._tag(e.kind, Color("cfe3f5")))
		var sl := UIKit.label(e.src, 13, UIKit.TEXT_MUTED)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(sl)
		for l in String(e.text).split("\n", false):
			var t := _text(l, 16)
			if _is_code(l):
				t.add_theme_font_override("font", UIKit.mono())
			v.add_child(t)
		var ans := String(e.get("answer", ""))
		if ans == "" and not e.has("code"):
			continue
		if _shown.has(i):
			if ans != "":
				v.add_child(_text("答案：" + ans, 16, UIKit.TEXT_GREEN))
			if e.has("code"):
				_mono_box(v, e.code)
		else:
			var b := UIKit.focusable(UIKit.button("看參考程式" if e.has("code") else "看答案", _show_answer.bind(i)))
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			v.add_child(b)


func _show_answer(i: int) -> void:
	_shown[i] = true
	var y := body_scroll.scroll_vertical
	_go(step)
	await get_tree().process_frame
	body_scroll.scroll_vertical = y
