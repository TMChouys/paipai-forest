class_name StoreBook
extends Control
## 雜貨店的商品清單（功能選單「雜貨店」打開）。
## 商品清單就是知識地圖：左邊是貨架（知識地圖 A～K），右邊是這一排的商品，分「基礎」和「進階」。
## 每件商品是一個委託：老闆把委託交給派派狼，派派鼠完成後，老闆把家具送到家。
## 先備的貨還沒到（先備概念的委託還沒完成）→「還沒到貨」：要先有基礎的貨，工匠廠商才做得出進階家具。

signal closed

const GREETINGS := [
	"歡迎光臨～！今天想看看什麼呀？",
	"哇，你來啦！這件好適合你喔！",
	"慢慢挑～有喜歡的就去找派派狼接委託！",
	"還沒到貨的別擔心，基礎的貨到了，工匠就做得出來！",
]
const COVER := Color("c98a3d")   # 拉布拉多的金黃色

var kmap: Dictionary = {}
var concepts: Dictionary = {}
var furniture: Dictionary = {}
var rewards: Dictionary = {}       # 遊戲任務 id -> 家具 id
var progress: Dictionary = {}      # 遊戲任務 id -> 星星
var area_id := "A"

var shelf_box: VBoxContainer
var title_l: Label
var sub_l: Label
var greet_l: Label
var body: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	visible = false
	kmap = QuestBook.load_map()
	for c in kmap.get("concepts", []):
		concepts[c.id] = c
	var f := FileAccess.open("res://data/furniture.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else {}
	if d is Dictionary:
		furniture = d.get("types", {})
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
	var bst := UIKit.panel_style(COVER, 22, UIKit.INK, 3)
	bst.set_content_margin_all(12)
	book.add_theme_stylebox_override("panel", bst)
	add_child(book)
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 4)
	book.add_child(pages)
	var pst := UIKit.panel_style(Color("fff8ec"), 14, UIKit.INK, 2)
	pst.shadow_size = 0

	# ---- 左頁：貨架（知識地圖分類） ----
	var left := PanelContainer.new()
	left.custom_minimum_size.x = 290
	left.add_theme_stylebox_override("panel", pst)
	pages.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	left.add_child(lv)
	var t := UIKit.label("雜貨店", 24)
	t.add_theme_font_override("font", UIKit.font_bold())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(t)
	var sub := UIKit.label("商品清單・照知識地圖排的貨架", 13, Color("8a6a50"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(sub)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	shelf_box = VBoxContainer.new()
	shelf_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelf_box.add_theme_constant_override("separation", 3)
	sc.add_child(shelf_box)

	# ---- 右頁：這一排貨架的商品 ----
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
	sub_l = UIKit.label("", 14, Color("8a6a50"))
	tv.add_child(sub_l)
	var x := UIKit.focusable(UIKit.button("×", close, "關閉（Esc）"))
	x.custom_minimum_size = Vector2(36, 36)
	x.add_theme_font_size_override("font_size", 20)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rh.add_child(x)
	greet_l = UIKit.label("", 16)
	greet_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gst := UIKit.panel_style(Color("fde9c8"), 12, Color("c98a3d"), 2)
	gst.shadow_size = 0
	gst.set_content_margin_all(8)
	greet_l.add_theme_stylebox_override("normal", gst)
	rv.add_child(greet_l)
	var bs := ScrollContainer.new()
	bs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(bs)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	bs.add_child(body)


## game_tasks：遊戲裡的任務（拿 reward 的家具）；stars：完成紀錄（任務 id -> 星星）
func open(game_tasks: Array, stars: Dictionary) -> void:
	rewards.clear()
	for gt in game_tasks:
		var fid: String = gt.get("reward", {}).get("furniture", "")
		if fid != "":
			rewards[gt.id] = fid
	progress = stars
	visible = true
	greet_l.text = "拉布拉多老闆：「%s」" % GREETINGS[randi() % GREETINGS.size()]
	show_area(area_id)


func close() -> void:
	visible = false
	closed.emit()


func _area(aid: String) -> Dictionary:
	for a in kmap.get("areas", []):
		if a.id == aid:
			return a
	return {}


func _tasks_in(aid: String) -> Array:
	return kmap.get("tasks", []).filter(func(t): return t.area == aid)


## 委託完成了沒（知識地圖的任務對到遊戲任務）
func is_done(t: Dictionary) -> bool:
	var gid := _gid(t)
	return gid != "" and int(progress.get(gid, 0)) > 0


func _gid(t: Dictionary) -> String:
	var g = t.get("game_task")
	return g if g is String else ""


## 概念的貨到了沒：有一個用到這個概念的委託完成了
func concept_stocked(cid: String) -> bool:
	for t in kmap.get("tasks", []):
		if t.concepts.has(cid) and is_done(t):
			return true
	return false


## 還缺哪些先備的貨（先備概念的名字）
func missing_prereqs(t: Dictionary) -> Array:
	var miss: Array = []
	for cid in t.concepts:
		for p in concepts.get(cid, {}).get("prereqs", []):
			if not concept_stocked(p) and not t.concepts.has(p):
				var n: String = concepts.get(p, {}).get("name", p)
				if not miss.has(n):
					miss.append(n)
	return miss


## 商品狀態：done 已送到家／stock 有貨／making 工匠還在做／wait 還沒到貨
func state(t: Dictionary) -> String:
	if is_done(t):
		return "done"
	if not missing_prereqs(t).is_empty():
		return "wait"
	return "stock" if t.status == "playable" else "making"


func show_area(aid: String) -> void:
	area_id = aid
	_fill_shelves()
	var a := _area(aid)
	title_l.text = "%s　%s" % [aid, a.get("name", "")]
	sub_l.text = a.get("summary", "")
	for n in body.get_children():
		n.queue_free()
	var ts := _tasks_in(aid)
	for basic in [true, false]:
		var part := ts.filter(func(t): return (int(t.difficulty) <= 2) == basic)
		if part.is_empty():
			continue
		var h := UIKit.label("基礎的貨" if basic else "進階的貨（要先有基礎的貨，工匠才做得出來）", 17, Color("8a5a20"))
		h.add_theme_font_override("font", UIKit.font_bold())
		body.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(grid)
		for t in part:
			grid.add_child(_card(t))


func _fill_shelves() -> void:
	for n in shelf_box.get_children():
		n.queue_free()
	for a in kmap.get("areas", []):
		var ts := _tasks_in(a.id)
		if ts.is_empty():
			continue
		var n_in := ts.filter(func(t): return state(t) != "wait").size()
		var b := UIKit.focusable(UIKit.button("%s　%s　到貨 %d/%d" % [a.id, a.name, n_in, ts.size()], show_area.bind(a.id), a.summary))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var st := UIKit.panel_style(Color(a.color).lightened(0.5), 10, UIKit.INK, 3 if a.id == area_id else 1)
		st.shadow_size = 0
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		shelf_box.add_child(b)


func _card(t: Dictionary) -> Control:
	var s := state(t)
	var bg: Color = {"done": Color("e3f1dc"), "stock": Color("fffdf6"), "making": Color("f6efe2"), "wait": Color("ece6dc")}[s]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cst := UIKit.panel_style(bg, 10, UIKit.INK if s == "stock" else Color("cdb79a"), 2 if s == "stock" else 1)
	cst.shadow_size = 0
	cst.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", cst)
	card.tooltip_text = str(t.get("story", ""))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var fid: String = rewards.get(_gid(t), "")
	var fname: String = furniture.get(fid, {}).get("name", "") if fid != "" else ""
	var faded := s == "wait"
	var name_l := UIKit.label(fname if fname != "" else "神秘家具", 17, Color("9a8c7a") if faded else UIKit.INK)
	name_l.add_theme_font_override("font", UIKit.font_bold())
	v.add_child(name_l)
	var line := UIKit.label("委託〈%s〉　%s" % [t.title, "★".repeat(int(t.difficulty))], 14, Color("9a8c7a") if faded else Color("6a5040"))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)
	var cn: Array = t.concepts.map(func(c): return concepts.get(c, {}).get("name", c))
	var cl := UIKit.label("學的是：" + "、".join(cn), 13, Color("9a8c7a"))
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cl)
	var msg := ""
	var col := UIKit.INK
	match s:
		"done":
			msg = "✓ 已經送到家了"
			col = UIKit.TEXT_GREEN
		"stock":
			msg = "有貨！去找派派狼接委託"
			col = Color("b5651d")
		"making":
			msg = "有貨了，工匠還在做（委託準備中）"
			col = Color("8a6a50")
		"wait":
			msg = "還沒到貨：要先有「%s」的貨" % "、".join(missing_prereqs(t))
			col = Color("a04a3a")
	var ml := UIKit.label(msg, 14, col)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ml)
	return card
