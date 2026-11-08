class_name ExamPanel
extends Control
## 三花奶奶的考核（在圖書館的閱讀教室點三花奶奶打開）＋黑貓弟弟的檢討筆記（點黑貓弟弟打開）。
## 學習內容切成四關（data/exams.json）。每一關考這個範圍裡：
##   全部的選擇題＝慢慢館長每一課的選擇練習；全部的實作題＝派派狼的委託（知識地圖對到的遊戲任務）。
## 一題都不能少、有計時、全部答對才過關。實作題沒有角色演出，只有純文字的系統輸出（像真的在電腦上寫程式）。
## 沒過：奶奶累了，要等 retry_wait_sec 秒才能重考；哪裡錯了去問黑貓弟弟。
## 存檔：save.exams[eid] = {passed, tries, next_at, last: {time, score, total, review: [...]}}

signal changed     # 存檔內容變了（main 負責寫檔）
signal closed

const EXAM_PATH := "res://data/exams.json"
const LESSON_PATH := "res://data/curriculum/lessons.json"
const CON_BG := Color("1f2421")
const CON_INK := Color("e6e6dc")
const LETTERS := ["A", "B", "C", "D", "E"]

var cfg: Dictionary = {}
var exams: Array = []
var questions: Dictionary = {}    # eid -> [{kind:"mc", cid, title, q, options, answer, why} | {kind:"code", tid, title, task}]
var lesson_ids: Dictionary = {}   # eid -> [concept id]
var task_ids: Dictionary = {}     # eid -> [task id]
var save: Dictionary = {}

var mode := ""                    # intro / exam / result / review
var eid := "E1"
var qi := 0                       # 目前第幾題
var answers: Array = []           # 選擇題：選了第幾個（-1 沒選）；實作題：程式碼
var remaining := 0.0
var force := false                # 開發用：不檢查條件

var frame: PanelContainer
var root_box: VBoxContainer
var timer_l: Label
var progress_l: Label
var nav_grid: GridContainer
var content: VBoxContainer
var editor: CodeEdit
var console: RichTextLabel
var input_row: HBoxContainer
var input_edit: LineEdit
var _con_inputs: Array = []
var _con_text := ""
var _tick := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.1, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	frame = PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -620
	frame.offset_right = 620
	frame.offset_top = -345
	frame.offset_bottom = 345
	add_child(frame)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	frame.add_child(root_box)


## 載入考試範圍：tasks = 遊戲任務（TaskRunner.list_tasks()）
func setup(tasks: Array) -> void:
	var f := FileAccess.open(EXAM_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	cfg = d if d is Dictionary else {}
	exams = cfg.get("exams", [])
	var kmap := QuestBook.load_map()
	var lf := FileAccess.open(LESSON_PATH, FileAccess.READ)
	var ld = JSON.parse_string(lf.get_as_text()) if lf else {}
	var lessons: Dictionary = ld.get("lessons", {}) if ld is Dictionary else {}
	var area_of: Dictionary = {}
	var cname: Dictionary = {}
	for c in kmap.get("concepts", []) + (ld.get("extra_concepts", []) if ld is Dictionary else []):
		area_of[c.id] = c.area
		cname[c.id] = c.get("name", c.id)
	var task_area: Dictionary = {}
	for kt in kmap.get("tasks", []):
		if kt.get("game_task", "") != "":
			task_area[kt.game_task] = kt.area
	var by_id: Dictionary = {}
	for t in tasks:
		by_id[t.id] = t
	for e in exams:
		var qs: Array = []
		var lids: Array = []
		var tids: Array = []
		for cid in lessons:
			if area_of.get(cid, "") in e.areas and lessons[cid].get("quiz") is Dictionary:
				var qz: Dictionary = lessons[cid].quiz
				lids.append(cid)
				qs.append({"kind": "mc", "cid": cid, "title": cname.get(cid, cid), "q": qz.q, "options": qz.options, "answer": int(qz.answer), "why": qz.get("why", "")})
		var code_ts: Array = []
		for t in tasks:
			if task_area.get(t.id, "") in e.areas:
				code_ts.append(t)
		code_ts.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
		for t in code_ts:
			tids.append(t.id)
			qs.append({"kind": "code", "tid": t.id, "title": t.get("title", t.id), "task": t})
		questions[e.id] = qs
		lesson_ids[e.id] = lids
		task_ids[e.id] = tids


# ---------------- 狀態 ----------------
func _rec(id: String) -> Dictionary:
	if not save.has("exams"):
		save.exams = {}
	if not save.exams.has(id):
		save.exams[id] = {"passed": false, "tries": 0, "next_at": 0.0}
	return save.exams[id]


func is_passed(id: String) -> bool:
	return bool(save.get("exams", {}).get(id, {}).get("passed", false))


## 奶奶還要休息幾秒（0 = 可以考）
func wait_left(id: String) -> int:
	var nx := float(save.get("exams", {}).get(id, {}).get("next_at", 0.0))
	return maxi(0, int(ceil(nx - Time.get_unix_time_from_system())))


## 現在該考哪一關（第一個還沒合格的；都合格了就是最後一關）
func current_exam() -> String:
	for e in exams:
		if not is_passed(e.id):
			return e.id
	return exams[-1].id if not exams.is_empty() else "E1"


## 考試條件：[{text, ok, hint}]
func requirements(id: String) -> Array:
	var out: Array = []
	var idx := _index(id)
	if idx > 0:
		var prev: Dictionary = exams[idx - 1]
		out.append({"text": "%s合格" % prev.title, "ok": is_passed(prev.id), "hint": "先通過%s。" % prev.title})
	var done: Array = save.get("lessons_done", [])
	var n_l := 0
	var miss_l: Array = []
	for cid in lesson_ids.get(id, []):
		if cid in done:
			n_l += 1
		else:
			miss_l.append(cid)
	out.append({"text": "慢慢館長的課：完成 %d／%d 堂" % [n_l, lesson_ids.get(id, []).size()], "ok": miss_l.is_empty(),
		"hint": "到圖書館找館長上課，選擇練習答對才算完成。"})
	var tids: Array = task_ids.get(id, [])
	if not tids.is_empty():
		var n_t := 0
		for tid in tids:
			if int(save.get("stars", {}).get(tid, 0)) > 0:
				n_t += 1
		out.append({"text": "派派狼的委託：完成 %d／%d 個" % [n_t, tids.size()], "ok": n_t == tids.size(),
			"hint": "找派派狼或派派兔接委託，交件通過才算完成。"})
	return out


func is_ready(id: String) -> bool:
	for r in requirements(id):
		if not r.ok:
			return false
	return true


func _index(id: String) -> int:
	for i in exams.size():
		if exams[i].id == id:
			return i
	return 0


func _exam(id: String) -> Dictionary:
	return exams[_index(id)]


func time_limit(id: String) -> int:
	var sec := 0
	for q in questions.get(id, []):
		sec += int(cfg.get("sec_per_mc", 60)) if q.kind == "mc" else int(cfg.get("sec_per_task", 360))
	return sec


# ---------------- 開關 ----------------
func open_intro(s: Dictionary, id: String = "") -> void:
	save = s
	eid = id if id != "" else current_exam()
	mode = "intro"
	visible = true
	_show_intro()


func open_review(s: Dictionary, id: String = "") -> void:
	save = s
	mode = "review"
	eid = id
	if eid == "":
		for e in exams:
			if save.get("exams", {}).get(e.id, {}).has("last"):
				eid = e.id
	visible = true
	_show_review()


func close() -> void:
	if mode == "exam":
		return   # 考試中不能離開，只能交卷
	visible = false
	mode = ""
	closed.emit()


func has_review() -> bool:
	for e in exams:
		if save.get("exams", {}).get(e.id, {}).has("last"):
			return true
	return false


func _clear() -> void:
	for c in root_box.get_children():
		c.queue_free()
	editor = null
	console = null


func _style(bg: Color) -> void:
	var st := UIKit.panel_style(bg, 20, UIKit.INK, 3)
	st.set_content_margin_all(14)
	frame.add_theme_stylebox_override("panel", st)


func _title_row(text: String, sub: String, closable: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	row.add_child(tv)
	var t := UIKit.label(text, 26)
	t.add_theme_font_override("font", UIKit.font_bold())
	tv.add_child(t)
	if sub != "":
		tv.add_child(UIKit.label(sub, 14, UIKit.TEXT_MUTED))
	if closable:
		var x := UIKit.focusable(UIKit.button("×", close, "關閉（Esc）"))
		x.custom_minimum_size = Vector2(36, 36)
		x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(x)
	root_box.add_child(row)
	return row


func _tabs(cb: Callable, mark: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for e in exams:
		var b := UIKit.focusable(UIKit.button("%s %s" % [e.title, mark.call(e.id)], cb.bind(e.id)))
		if e.id == eid:
			UIKit.primary(b)
		row.add_child(b)
	root_box.add_child(row)


func _card(parent: Control, bg: Color, border: Color = Color("d8c3a5")) -> VBoxContainer:
	var p := PanelContainer.new()
	var st := UIKit.panel_style(bg, 12, border, 2)
	st.shadow_size = 0
	st.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


func _text(t: String, size: int = 17, color: Color = UIKit.INK) -> Label:
	var l := UIKit.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _mono(parent: Control, t: String, bg: Color = CON_BG, ink: Color = CON_INK) -> void:
	var p := PanelContainer.new()
	var st := UIKit.panel_style(bg, 8, UIKit.INK, 1)
	st.shadow_size = 0
	st.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", st)
	var l := UIKit.label(t, 16, ink)
	l.add_theme_font_override("font", UIKit.mono())
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	p.add_child(l)
	parent.add_child(p)


func _scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return v


static func _fmt_time(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


# ---------------- 考試說明（點三花奶奶） ----------------
func _show_intro() -> void:
	_clear()
	_style(Color("fbf4ff"))
	var e := _exam(eid)
	_title_row("三花奶奶的考核", "「慢慢想，奶奶等你。」・全部答對才過關")
	_tabs(func(id): eid = id; _show_intro(), func(id): return "✓ 合格" if is_passed(id) else "")
	var body := _scroll(root_box)
	var qs: Array = questions.get(eid, [])
	var n_mc := 0
	for q in qs:
		if q.kind == "mc":
			n_mc += 1
	var info := _card(body, Color("fffdf6"))
	var h := _text("%s：%s（%s）" % [e.title, e.name, e.chapters], 21)
	h.add_theme_font_override("font", UIKit.font_bold())
	info.add_child(h)
	info.add_child(_text("選擇題 %d 題（館長的課）＋實作題 %d 題（派派狼的委託），一共 %d 題，時間 %d 分鐘。" % [n_mc, qs.size() - n_mc, qs.size(), time_limit(eid) / 60]))
	var rules := _card(body, Color("fffdf6"))
	var rh := _text("考試規則", 18, UIKit.TEXT_INFO)
	rules.add_child(rh)
	for r in ["全部的題目一題都不能少，全部答對才過關。",
			"實作題沒有角色演出，按「▶ 執行」只會看到程式印出來的文字，就像真的在電腦上寫程式。",
			"時間到會自動交卷。",
			"沒過關的話，奶奶累了要休息 %d 分鐘，休息完才能重考。" % (int(cfg.get("retry_wait_sec", 300)) / 60),
			"想知道哪裡錯了，去找奶奶的孫子黑貓弟弟檢討。"]:
		rules.add_child(_text("・" + r, 16))
	var req := _card(body, Color("fffdf6"))
	req.add_child(_text("考試條件", 18, UIKit.TEXT_INFO))
	for r in requirements(eid):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var mk := UIKit.label("✓" if r.ok else "✗", 20, UIKit.TEXT_GREEN if r.ok else UIKit.TEXT_RED)
		mk.custom_minimum_size.x = 24
		row.add_child(mk)
		row.add_child(_text(r.text, 17))
		req.add_child(row)
		if not r.ok:
			req.add_child(_text("　　提示：" + r.hint, 15, UIKit.TEXT_MUTED))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root_box.add_child(foot)
	var msg := ""
	var can := true
	var wl := wait_left(eid)
	if is_passed(eid):
		msg = "這一關已經合格了！要再考一次練習也可以。"
	if wl > 0:
		msg = "奶奶累了，休息一下……還要 %s 才能重考。先去找黑貓弟弟檢討吧。" % _fmt_time(wl)
		can = false
	elif not is_ready(eid) and not force:
		msg = "還沒準備好喔。上面打 ✗ 的條件都完成了，再來找奶奶。"
		can = false
	if qs.is_empty():
		msg = "這一關還沒有題目。"
		can = false
	var ml := _text(msg, 16, UIKit.TEXT_WARN)
	foot.add_child(ml)
	var go := UIKit.primary(UIKit.focusable(UIKit.button("開始考試", _start)))
	go.disabled = not can
	foot.add_child(go)


# ---------------- 考試中 ----------------
func _start() -> void:
	var qs: Array = questions.get(eid, [])
	answers.clear()
	for q in qs:
		answers.append(-1 if q.kind == "mc" else String(q.task.get("starter_code", "")))
	remaining = float(time_limit(eid))
	mode = "exam"
	qi = 0
	_show_exam()


func _process(delta: float) -> void:
	if not visible:
		return
	if mode == "exam":
		remaining -= delta
		if timer_l:
			timer_l.text = "⏱ " + _fmt_time(maxi(0, int(ceil(remaining))))
			timer_l.add_theme_color_override("font_color", UIKit.TEXT_RED if remaining < 300 else UIKit.INK)
		if remaining <= 0:
			_grade(true)
	elif mode == "intro" and float(save.get("exams", {}).get(eid, {}).get("next_at", 0.0)) > 0:
		_tick += delta
		if _tick >= 1.0:   # 奶奶休息的倒數：每秒更新一次
			_tick = 0.0
			if wait_left(eid) == 0:
				_rec(eid).next_at = 0.0
			_show_intro()


func _answered(i: int) -> bool:
	var q: Dictionary = questions[eid][i]
	if q.kind == "mc":
		return int(answers[i]) >= 0
	return String(answers[i]).strip_edges() != String(q.task.get("starter_code", "")).strip_edges()


func _show_exam() -> void:
	_clear()
	_style(Color("f7f4ee"))
	var e := _exam(eid)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root_box.add_child(top)
	var t := UIKit.label("三花奶奶的考核・%s　%s" % [e.title, e.name], 22)
	t.add_theme_font_override("font", UIKit.font_bold())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	progress_l = UIKit.label("", 17, UIKit.TEXT_MUTED)
	top.add_child(progress_l)
	timer_l = UIKit.label("⏱ " + _fmt_time(int(remaining)), 22)
	timer_l.add_theme_font_override("font", UIKit.mono())
	top.add_child(timer_l)
	var sub := UIKit.primary(UIKit.focusable(UIKit.button("交卷", _confirm_submit)))
	top.add_child(sub)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	root_box.add_child(mid)
	# 左：題號
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 196
	mid.add_child(left)
	left.add_child(UIKit.label("題號", 15, UIKit.TEXT_MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	nav_grid = GridContainer.new()
	nav_grid.columns = 4
	nav_grid.add_theme_constant_override("h_separation", 4)
	nav_grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(nav_grid)
	left.add_child(UIKit.label("■ 已作答　□ 還沒作答\n選＝選擇題　寫＝實作題", 13, UIKit.TEXT_MUTED))
	# 右：題目
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	mid.add_child(content)
	_goto(qi)


func _refresh_nav() -> void:
	if nav_grid == null:
		return
	for c in nav_grid.get_children():
		c.queue_free()
	var qs: Array = questions[eid]
	var n := 0
	for i in qs.size():
		var done := _answered(i)
		if done:
			n += 1
		var b := UIKit.button("%d%s" % [i + 1, "選" if qs[i].kind == "mc" else "寫"], _goto.bind(i))
		b.custom_minimum_size = Vector2(44, 36)
		var col := Color("cfe3f5") if done else Color("fffdf6")
		var st := UIKit.panel_style(col, 8, UIKit.ACCENT_LINE if i == qi else UIKit.INK, 3 if i == qi else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		nav_grid.add_child(b)
	progress_l.text = "已作答 %d／%d" % [n, qs.size()]


func _keep_code() -> void:
	if editor != null and is_instance_valid(editor) and qi < answers.size() and questions[eid][qi].kind == "code":
		answers[qi] = editor.text


func _goto(i: int) -> void:
	_keep_code()
	qi = clampi(i, 0, questions[eid].size() - 1)
	for c in content.get_children():
		c.queue_free()
	editor = null
	console = null
	var q: Dictionary = questions[eid][qi]
	if q.kind == "mc":
		_show_mc(q)
	else:
		_show_code(q)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	content.add_child(nav)
	var pb := UIKit.focusable(UIKit.button("← 上一題", func(): _goto(qi - 1)))
	pb.disabled = qi == 0
	nav.add_child(pb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(sp)
	var nb := UIKit.focusable(UIKit.button("下一題 →", func(): _goto(qi + 1)))
	nb.disabled = qi >= questions[eid].size() - 1
	nav.add_child(nb)
	_refresh_nav()


func _show_mc(q: Dictionary) -> void:
	var body := _scroll(content)
	body.add_child(_text("第 %d 題　選擇題" % (qi + 1), 15, UIKit.TEXT_INFO))
	var lines: PackedStringArray = String(q.q).split("\n")
	var h := _text(lines[0], 21)
	h.add_theme_font_override("font", UIKit.font_bold())
	body.add_child(h)
	if lines.size() > 1:
		_mono(body, "\n".join(lines.slice(1)))
	var pick := int(answers[qi])
	for i in q.options.size():
		var b := UIKit.focusable(UIKit.button("%s　%s" % [LETTERS[i], q.options[i]], _pick_mc.bind(i)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UIKit.mono())
		if i == pick:
			var st := UIKit.panel_style(Color("cfe3f5"), 10, UIKit.BLUE, 3)
			st.shadow_size = 0
			b.add_theme_stylebox_override("normal", st)
			b.add_theme_stylebox_override("hover", st)
			b.text += "　◀ 你的答案"
		body.add_child(b)


func _pick_mc(i: int) -> void:
	answers[qi] = i
	_goto(qi)


func _show_code(q: Dictionary) -> void:
	var t: Dictionary = q.task
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	# 題目
	var sheet := _scroll(row)
	sheet.get_parent().custom_minimum_size.x = 400
	sheet.get_parent().size_flags_horizontal = Control.SIZE_FILL
	sheet.add_child(_text("第 %d 題　實作題〈%s〉" % [qi + 1, q.title], 15, UIKit.TEXT_INFO))
	var parts := TaskPanel.build_sheet(t)
	for key in ["goal", "write", "limit"]:
		var title: String = {"goal": "題目", "write": "撰寫規定", "limit": "限制條件"}[key]
		var c := _card(sheet, Color("fffdf6"))
		c.add_child(_text(title, 16, UIKit.TEXT_INFO))
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.add_theme_color_override("default_color", UIKit.INK)
		r.add_theme_font_size_override("normal_font_size", 16)
		r.add_theme_font_size_override("bold_font_size", 16)
		r.add_theme_font_override("mono_font", UIKit.mono())
		r.text = parts[key]
		c.add_child(r)
	var c2 := _card(sheet, Color("fffdf6"))
	c2.add_child(_text("範例執行結果", 16, UIKit.TEXT_INFO))
	_mono(c2, sample_output(t))
	# 程式＋系統輸出
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	editor = CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_theme_font_override("font", UIKit.mono())
	editor.add_theme_font_size_override("font_size", 17)
	editor.gutters_draw_line_numbers = true
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 4
	editor.auto_brace_completion_enabled = true
	editor.syntax_highlighter = _highlighter()
	var est := UIKit.panel_style(Color("fffdf6"), 8, UIKit.INK, 1)
	est.shadow_size = 0
	editor.add_theme_stylebox_override("normal", est)
	editor.add_theme_color_override("font_color", UIKit.INK)
	editor.text = String(answers[qi])
	editor.text_changed.connect(func():
		answers[qi] = editor.text
		_refresh_nav())
	right.add_child(editor)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	right.add_child(bar)
	bar.add_child(UIKit.primary(UIKit.focusable(UIKit.button("▶ 執行", _run_code, "執行你的程式，看印出來的文字"))))
	bar.add_child(UIKit.focusable(UIKit.button("清除輸出", func(): _con_set(""))))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	bar.add_child(UIKit.label("執行結果（系統輸出）", 14, UIKit.TEXT_MUTED))
	console = RichTextLabel.new()
	console.custom_minimum_size.y = 170
	console.bbcode_enabled = true
	console.scroll_following = true
	console.selection_enabled = true
	console.add_theme_font_override("normal_font", UIKit.mono())
	console.add_theme_font_size_override("normal_font_size", 16)
	console.add_theme_color_override("default_color", CON_INK)
	var cst := UIKit.panel_style(CON_BG, 8, UIKit.INK, 1)
	cst.shadow_size = 0
	cst.set_content_margin_all(8)
	console.add_theme_stylebox_override("normal", cst)
	right.add_child(console)
	input_row = HBoxContainer.new()
	input_row.visible = false
	right.add_child(input_row)
	input_row.add_child(UIKit.label("輸入：", 15))
	input_edit = LineEdit.new()
	input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_edit.add_theme_font_override("font", UIKit.mono())
	input_edit.text_submitted.connect(func(_s): _send_input())
	input_row.add_child(input_edit)
	input_row.add_child(UIKit.focusable(UIKit.button("送出 ⏎", _send_input)))
	_con_set("[color=#8f9a8f]按「▶ 執行」跑你的程式。[/color]")


static func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("a8551f")
	h.symbol_color = Color("6b5242")
	h.function_color = Color("2a6fa3")
	h.member_variable_color = Color("7a4fa3")
	for kw in ["if", "elif", "else", "while", "for", "in", "and", "or", "not", "pass", "break", "continue", "import", "from", "def", "return", "as", "try", "except", "with"]:
		h.add_keyword_color(kw, Color("c2407a"))
	for kw in ["True", "False", "None"]:
		h.add_keyword_color(kw, Color("a8551f"))
	for f in ["print", "input", "len", "str", "int", "float", "range", "abs", "min", "max", "round"]:
		h.add_keyword_color(f, Color("2a6fa3"))
	h.add_color_region("\"", "\"", Color("2f7a3f"), true)
	h.add_color_region("'", "'", Color("2f7a3f"), true)
	h.add_color_region("#", "", Color("76644f"), true)
	return h


## 範例執行結果：用標準答案跑第一組（看得到的）測資
static func sample_output(t: Dictionary) -> String:
	var test: Dictionary = {}
	for tc in t.get("tests", []):
		if not tc.get("hidden", false):
			test = tc
			break
	var sub := TaskRunner.substitute_given(String(t.get("reference", "")), test.get("vars", {}))
	var res := PyInterp.run(sub.code, {"builtins": t.get("builtins", PyInterp.BUILTINS), "modules": t.get("modules", {}), "inputs": test.get("inputs", [])})
	var out := ""
	for ev in res.trace:
		if ev.type == "print":
			out += String(ev.text) + "\n"
		elif ev.type == "input":
			out += String(ev.prompt) + String(ev.value) + "\n"
	return out.strip_edges(false, true) if out != "" else "（沒有輸出）"


func _con_set(bb: String) -> void:
	_con_text = bb
	if console:
		console.text = bb


func _run_code() -> void:
	_keep_code()
	_con_inputs = []
	_run_once()


func _run_once() -> void:
	var t: Dictionary = questions[eid][qi].task
	var res := PyInterp.run(String(answers[qi]), {"builtins": t.get("builtins", PyInterp.BUILTINS), "modules": t.get("modules", {}), "inputs": _con_inputs})
	var bb := "[color=#8f9a8f]$ python main.py[/color]\n"
	if res.ast == null:
		bb += "[color=#ff8a80]%s[/color]\n" % UIKit.esc(res.error.get("message", "語法錯誤"))
		input_row.visible = false
		_con_set(bb)
		return
	for ev in res.trace:
		match ev.type:
			"print":
				bb += UIKit.esc(String(ev.text)) + "\n"
			"input":
				bb += UIKit.esc(String(ev.prompt)) + "[color=#9fd3e6]" + UIKit.esc(String(ev.value)) + "[/color]\n"
			"error":
				bb += "[color=#ff8a80]%s：%s[/color]\n" % [UIKit.esc(ev.error.kind), UIKit.esc(ev.error.message)]
	if not res.need_input.is_empty() and _con_inputs.size() < 30:
		bb += UIKit.esc(String(res.need_input.prompt))
		input_row.visible = true
		input_edit.text = ""
		input_edit.grab_focus()
	else:
		input_row.visible = false
		bb += "[color=#8f9a8f]（程式結束）[/color]"
	_con_set(bb)


func _send_input() -> void:
	if not input_row.visible:
		return
	_con_inputs.append(input_edit.text)
	_run_once()


# ---------------- 交卷、計分 ----------------
func _confirm_submit() -> void:
	_keep_code()
	var left := 0
	for i in questions[eid].size():
		if not _answered(i):
			left += 1
	var dlg := ConfirmationDialog.new()
	dlg.title = "交卷"
	dlg.dialog_text = ("還有 %d 題沒作答。\n" % left if left > 0 else "") + "確定要交卷嗎？交了就不能再改囉。"
	dlg.ok_button_text = "交卷"
	dlg.cancel_button_text = "再檢查一下"
	dlg.theme = UIKit.theme()
	add_child(dlg)
	dlg.confirmed.connect(func(): _grade(false))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


## 計分：選擇題對答案；實作題用派派狼的檢查器，要「滿分」（通過而且沒有任何扣分）才算對
func grade_answers(id: String, ans: Array) -> Dictionary:
	var review: Array = []
	var score := 0
	var qs: Array = questions[id]
	for i in qs.size():
		var q: Dictionary = qs[i]
		var item := {"kind": q.kind, "title": q.title}
		if q.kind == "mc":
			item.merge({"q": q.q, "options": q.options, "answer": q.answer, "pick": int(ans[i]), "why": q.why})
			item.ok = int(ans[i]) == int(q.answer)
		else:
			var code := String(ans[i])
			var rep := TaskChecker.evaluate(q.task, code)
			item.code = code
			item.ok = rep.passed and int(rep.warns) == 0
			var fs: Array = []
			for f in rep.findings:
				if f.severity != "info":
					fs.append({"severity": f.severity, "message": String(f.message), "hint": String(f.get("hint", ""))})
			item.findings = fs
			for c in rep.cases:
				if not c.ok:
					item.case = {"name": String(c.name), "expected": c.ref.get("outputs", []), "got": c.stu.get("outputs", [])}
					break
		if item.ok:
			score += 1
		review.append(item)
	return {"score": score, "total": qs.size(), "review": review}


func _grade(timeout: bool) -> void:
	if mode != "exam":
		return
	_keep_code()
	mode = "result"
	var g := grade_answers(eid, answers)
	var r := _rec(eid)
	r.tries = int(r.get("tries", 0)) + 1
	r.last = {"time": Time.get_unix_time_from_system(), "score": g.score, "total": g.total, "review": g.review, "timeout": timeout}
	var passed: bool = g.score == g.total
	if passed:
		r.passed = true
		r.next_at = 0.0
	else:
		r.next_at = Time.get_unix_time_from_system() + float(cfg.get("retry_wait_sec", 300))
	changed.emit()
	_show_result(g, passed, timeout)


func _show_result(g: Dictionary, passed: bool, timeout: bool) -> void:
	_clear()
	_style(Color("fbf4ff"))
	var e := _exam(eid)
	_title_row("三花奶奶的考核・%s" % e.title, "時間到，自動交卷" if timeout else "")
	var body := _scroll(root_box)
	var big := _text("合格！全部答對 %d／%d" % [g.score, g.total] if passed else "答對 %d／%d 題" % [g.score, g.total], 34,
		UIKit.TEXT_GREEN if passed else UIKit.TEXT_RED)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_override("font", UIKit.font_bold())
	body.add_child(big)
	var c := _card(body, Color("fffdf6"))
	if passed:
		c.add_child(_text("三花奶奶：「哎呀，真是個好孩子。一題都沒錯，%s合格了。」" % e.title, 19))
		c.add_child(_text("奶奶在你的考核卡上蓋了一個小貓掌印。", 16, UIKit.TEXT_MUTED))
	else:
		c.add_child(_text("三花奶奶：「還差 %d 題喔。答案就在眼前，看仔細一點。」" % (g.total - g.score), 19))
		c.add_child(_text("奶奶累了，要休息 %d 分鐘，休息完才能重考。" % (int(cfg.get("retry_wait_sec", 300)) / 60), 17, UIKit.TEXT_WARN))
		c.add_child(_text("想知道哪幾題錯了、為什麼錯，去閱讀教室找黑貓弟弟檢討。", 17))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	root_box.add_child(foot)
	foot.add_child(UIKit.primary(UIKit.focusable(UIKit.button("謝謝奶奶", close))))


# ---------------- 黑貓弟弟的檢討筆記 ----------------
func _show_review() -> void:
	_clear()
	_style(Color("f1f3f7"))
	_title_row("黑貓弟弟的檢討筆記", "「奶奶不說的，我偷偷告訴你。」・最近一次考試的每一題")
	_tabs(func(id): eid = id; _show_review(), func(id):
		var l: Dictionary = save.get("exams", {}).get(id, {}).get("last", {})
		return "" if l.is_empty() else "%d／%d" % [int(l.score), int(l.total)])
	var body := _scroll(root_box)
	var last: Dictionary = save.get("exams", {}).get(eid, {}).get("last", {})
	if last.is_empty():
		body.add_child(_text("黑貓弟弟：「這一關你還沒考過喔。考完再來找我！」", 19))
		return
	var wrong := 0
	for it in last.review:
		if not it.ok:
			wrong += 1
	body.add_child(_text("黑貓弟弟：「%s」" % ("全部都對！你好厲害。" if wrong == 0 else "錯了 %d 題，打 ✗ 的地方看仔細喔。" % wrong), 19))
	for i in last.review.size():
		var it: Dictionary = last.review[i]
		var c := _card(body, Color("eef8e8") if it.ok else Color("fdeceb"), UIKit.GREEN if it.ok else UIKit.RED)
		var head := _text("%s　第 %d 題（%s）%s" % ["✓" if it.ok else "✗", i + 1, "選擇題" if it.kind == "mc" else "實作題", it.title], 18,
			UIKit.TEXT_GREEN if it.ok else UIKit.TEXT_RED)
		head.add_theme_font_override("font", UIKit.font_bold())
		c.add_child(head)
		if it.kind == "mc":
			var lines: PackedStringArray = String(it.q).split("\n")
			c.add_child(_text(lines[0], 17))
			if lines.size() > 1:
				_mono(c, "\n".join(lines.slice(1)))
			var pick := int(it.pick)
			c.add_child(_text("你的答案：%s" % ("（沒作答）" if pick < 0 else "%s　%s" % [LETTERS[pick], it.options[pick]]), 16))
			if not it.ok:
				var a := int(it.answer)
				c.add_child(_text("正確答案：%s　%s" % [LETTERS[a], it.options[a]], 16, UIKit.TEXT_GREEN))
				c.add_child(_text("為什麼：" + String(it.why), 16))
		else:
			_mono(c, String(it.code) if String(it.code).strip_edges() != "" else "（沒有寫程式）", Color("fffdf6"), UIKit.INK)
			if not it.ok:
				for f in it.get("findings", []):
					var line := "✗ " + String(f.message)
					if String(f.hint) != "":
						line += "\n　提示：" + String(f.hint)
					c.add_child(_text(line, 16, UIKit.TEXT_RED if f.severity == "block" else UIKit.TEXT_WARN))
				if it.has("case"):
					c.add_child(_text("沒過的測資：" + String(it.case.name), 16))
					var both := HBoxContainer.new()
					both.add_theme_constant_override("separation", 8)
					c.add_child(both)
					for pair in [["應該印出", it.case.expected], ["你的程式印出", it.case.got]]:
						var v := VBoxContainer.new()
						v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						both.add_child(v)
						v.add_child(UIKit.label(pair[0], 14, UIKit.TEXT_MUTED))
						var arr: Array = pair[1]
						_mono(v, "\n".join(PackedStringArray(arr)) if not arr.is_empty() else "（沒有輸出）")
