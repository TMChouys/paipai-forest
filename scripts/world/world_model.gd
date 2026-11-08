class_name WorldModel
extends RefCounted
## 純邏輯的房間：格子、家具、派派鼠。不含任何畫面，方便測試與「先算後演」。
## 座標：x 向右（東），z 向下（南）。N = (0,-1)。
## 家具 item：{uid, type, cell:Vector2i(錨點=左上), rot:0..3, on:"父家具uid", wall:"N/E/S/W"}

const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const DIR_ORDER := ["N", "E", "S", "W"]

static var _defs: Dictionary = {}

var width := 8
var depth := 8
var items: Dictionary = {}  # uid -> item
var gopher_cell := Vector2i(0, 0)
var gopher_dir := "N"
var holding := ""
var spots: Dictionary = {}  # 名稱 -> {cell:Vector2i, face:"N"}
## 野外冒險：一起在場上的角色（派派狼、派派兔），程式也可以指揮他們。who -> {cell, dir, holding}
var actors: Dictionary = {}
var decor: Array = []      # 野外：只是裝飾、不擋路的東西 [{type, cell}]（野餐墊、草藥籃）
var lock_code := 0          # 石門的密碼（layout.lock.code；測資可以用 "lock" 換掉）
var lock_gate := ""         # 哪一件是石門（打開就消失）
var _cur := "gopher"        # 現在是誰在做動作
const STRONG := ["wolf"]    # 派派狼力氣大：搬得動重的東西（heavy）


static func defs() -> Dictionary:
	if _defs.is_empty():
		var f := FileAccess.open("res://data/furniture.json", FileAccess.READ)
		_defs = JSON.parse_string(f.get_as_text()).types
	return _defs


static func def_of(type: String) -> Dictionary:
	return defs().get(type, {"name": type, "size": [1, 1], "height": 1.0, "kind": "floor", "builder": "crate", "color": "#cccccc"})


static func from_layout(layout: Dictionary) -> WorldModel:
	var w := WorldModel.new()
	var sz: Array = layout.get("size", [8, 8])
	w.width = int(sz[0])
	w.depth = int(sz[1])
	for it in layout.get("furniture", []):
		var item := {"uid": it.uid, "type": it.type, "cell": Vector2i(int(it.cell[0]), int(it.cell[1])), "rot": int(it.get("rot", 0)),
			"on": it.get("on", ""), "wall": it.get("wall", "")}
		w.items[item.uid] = item
	var g: Dictionary = layout.get("gopher", {"cell": [0, 0], "dir": "N"})
	w.gopher_cell = Vector2i(int(g.cell[0]), int(g.cell[1]))
	w.gopher_dir = g.get("dir", "N")
	for n in layout.get("npcs", []):
		if layout.get("actors_move", false):
			w.actors[n.who] = {"cell": Vector2i(int(n.cell[0]), int(n.cell[1])), "dir": n.get("dir", "N"), "holding": ""}
	w.decor = layout.get("decor", [])
	var lk: Dictionary = layout.get("lock", {})
	w.lock_code = int(lk.get("code", 0))
	w.lock_gate = lk.get("gate", "")
	for name in layout.get("spots", {}):
		var s: Dictionary = layout.spots[name]
		w.spots[name] = {"cell": Vector2i(int(s.cell[0]), int(s.cell[1])), "face": s.get("face", "N")}
	return w


func to_layout() -> Dictionary:
	var arr: Array = []
	for uid in items:
		var it: Dictionary = items[uid]
		var d := {"uid": uid, "type": it.type, "cell": [it.cell.x, it.cell.y], "rot": it.rot}
		if it.on != "":
			d.on = it.on
		if it.wall != "":
			d.wall = it.wall
		arr.append(d)
	return {"size": [width, depth], "furniture": arr,
		"gopher": {"cell": [gopher_cell.x, gopher_cell.y], "dir": gopher_dir}}


func clone() -> WorldModel:
	var w := WorldModel.new()
	w.width = width
	w.depth = depth
	for uid in items:
		w.items[uid] = items[uid].duplicate()
	w.gopher_cell = gopher_cell
	w.gopher_dir = gopher_dir
	w.holding = holding
	w.spots = spots.duplicate(true)
	w.actors = actors.duplicate(true)
	w.lock_code = lock_code
	w.lock_gate = lock_gate
	return w


# ---------------- 格子查詢 ----------------
func in_room(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < depth


static func footprint_size(type: String, rot: int) -> Vector2i:
	var s: Array = def_of(type).size
	var v := Vector2i(int(s[0]), int(s[1]))
	return Vector2i(v.y, v.x) if rot % 2 == 1 else v


func footprint(item: Dictionary) -> Array:
	var cells: Array = []
	if item.wall != "" or item.on != "":
		return cells
	var sz := footprint_size(item.type, item.rot)
	for dx in range(sz.x):
		for dz in range(sz.y):
			cells.append(item.cell + Vector2i(dx, dz))
	return cells


## 這一格被哪個落地家具佔用（"" 表示空）
func floor_item_at(c: Vector2i, ignore: String = "") -> String:
	for uid in items:
		if uid == ignore or uid == holding or _held_by_actor(uid):
			continue
		var it: Dictionary = items[uid]
		if it.wall != "" or it.on != "":
			continue
		if c in footprint(it):
			return uid
	return ""


func is_free(c: Vector2i, ignore: String = "") -> bool:
	return in_room(c) and floor_item_at(c, ignore) == "" and c != gopher_cell


func walkable(c: Vector2i) -> bool:
	return in_room(c) and floor_item_at(c) == "" and not _occupied(c)


## 這一格有沒有站著別的角色（自己以外）
func _occupied(c: Vector2i) -> bool:
	if actors.is_empty():
		return false
	if _cur != "gopher" and c == _gopher_saved.get("cell", Vector2i(-99, -99)):
		return true
	for who in actors:
		if who != _cur and actors[who].cell == c:
			return true
	return false


func _held_by_actor(uid: String) -> bool:
	for who in actors:
		if who != _cur and actors[who].holding == uid:
			return true
	if _cur != "gopher" and _gopher_saved.get("holding", "") == uid:
		return true
	return false


var _gopher_saved: Dictionary = {}


## 換成別的角色來做動作：把他的狀態放進 gopher_* 欄位，做完再換回來
func _as_actor(who: String, act: String, args: Dictionary) -> Dictionary:
	if not actors.has(who):
		return {"ok": false, "act": act, "who": who, "reason": "%s不在這裡" % who}
	_gopher_saved = {"cell": gopher_cell, "dir": gopher_dir, "holding": holding}
	var a: Dictionary = actors[who]
	gopher_cell = a.cell
	gopher_dir = a.dir
	holding = a.holding
	_cur = who
	var res := apply(act, args)
	a.cell = gopher_cell
	a.dir = gopher_dir
	a.holding = holding
	gopher_cell = _gopher_saved.cell
	gopher_dir = _gopher_saved.dir
	holding = _gopher_saved.holding
	_cur = "gopher"
	_gopher_saved = {}
	res.who = who
	return res


func children_of(uid: String) -> Array:
	var out: Array = []
	for k in items:
		if items[k].on == uid:
			out.append(k)
	return out


## 檢查家具能不能放在某處（滑鼠擺放用）。回傳 "" 表示可以，否則是原因。
func can_place(type: String, cell: Vector2i, rot: int, uid: String = "", on: String = "", wall: String = "") -> String:
	var d := def_of(type)
	if wall != "":
		if d.kind != "wall":
			return "這件家具不能掛在牆上"
		for k in items:
			if k != uid and items[k].wall == wall and items[k].cell == cell:
				return "牆上這裡已經掛東西了"
		return ""
	if on != "":
		if d.kind != "top":
			return "這件家具太大，不能疊在上面"
		var parent: Dictionary = items.get(on, {})
		if parent.is_empty() or not def_of(parent.type).has("surface"):
			return "下面的家具不能放東西"
		for k in children_of(on):
			if k != uid:
				return "上面已經放東西了"
		return ""
	if d.kind == "wall":
		return "這件家具要掛在牆上"
	var sz := footprint_size(type, rot)
	for dx in range(sz.x):
		for dz in range(sz.y):
			var c := cell + Vector2i(dx, dz)
			if not in_room(c):
				return "超出房間範圍"
			if floor_item_at(c, uid) != "":
				return "和其他家具重疊"
	return ""


# ---------------- 動作（任務演出用）----------------
## 每個動作回傳 {ok, act, ...演出需要的資料, reason}
func apply(act: String, args: Dictionary = {}) -> Dictionary:
	var who: String = args.get("who", "gopher")
	if who != "gopher" and _cur == "gopher":
		var a2 := args.duplicate()
		a2.erase("who")
		return _as_actor(who, act, a2)
	match act:
		"open_gate":
			return _open_gate(int(args.get("code", 0)))
		"do":
			# 在指定地點做一件事（採花、照亮……）：要先走到那個地點
			var sp: String = args.get("spot", "")
			if sp != "" and spots.has(sp) and gopher_cell != spots[sp].cell:
				return {"ok": false, "act": "do", "reason": "要先走到%s才能%s" % [sp, args.get("verb", "做這件事")]}
			return {"ok": true, "act": "do", "text": str(args.get("text", "")), "dir": gopher_dir}
		"walk_to":
			return _walk_to(str(args.get("spot", "")))
		"forward":
			return _forward(int(args.get("n", 1)))
		"turn_left", "turn_right":
			var i := DIR_ORDER.find(gopher_dir)
			gopher_dir = DIR_ORDER[(i + (3 if act == "turn_left" else 1)) % 4]
			return {"ok": true, "act": act, "dir": gopher_dir}
		"pick_up":
			return _pick_up()
		"put_down":
			return _put_down()
		"push":
			return _push(int(args.get("n", 1)))
		"say":
			return {"ok": true, "act": "say", "text": str(args.get("text", ""))}
	return {"ok": false, "act": act, "reason": "派派鼠不會做「%s」" % act}


func front_cell() -> Vector2i:
	return gopher_cell + DIRS[gopher_dir]


func _walk_to(spot_name: String) -> Dictionary:
	if not spots.has(spot_name):
		return {"ok": false, "act": "walk_to", "reason": "房間裡找不到「%s」" % spot_name}
	var s: Dictionary = spots[spot_name]
	var path := find_path(gopher_cell, s.cell)
	if path.is_empty():
		return {"ok": false, "act": "walk_to", "path": [gopher_cell], "reason": "走不到「%s」，路被家具擋住了" % spot_name}
	gopher_cell = s.cell
	gopher_dir = s.face
	return {"ok": true, "act": "walk_to", "path": path, "dir": gopher_dir, "spot": spot_name}


func _forward(n: int) -> Dictionary:
	var path: Array = [gopher_cell]
	for i in range(n):
		var nxt: Vector2i = gopher_cell + DIRS[gopher_dir]
		if not walkable(nxt):
			return {"ok": false, "act": "forward", "path": path, "reason": "前面是%s，走不過去" % ("牆壁" if not in_room(nxt) else "家具")}
		gopher_cell = nxt
		path.append(nxt)
	return {"ok": true, "act": "forward", "path": path}


func _pick_up() -> Dictionary:
	if holding != "":
		return {"ok": false, "act": "pick_up", "reason": "手上已經拿著東西了，要先放下"}
	var uid := floor_item_at(front_cell())
	if uid == "":
		return {"ok": false, "act": "pick_up", "reason": "面前沒有家具可以搬"}
	var dd := def_of(items[uid].type)
	if not dd.get("carry", false) and not (dd.get("heavy", false) and _cur in STRONG):
		return {"ok": false, "act": "pick_up", "uid": uid, "reason": "%s太重了，搬不動" % def_of(items[uid].type).name}
	holding = uid
	return {"ok": true, "act": "pick_up", "uid": uid}


func _put_down() -> Dictionary:
	if holding == "":
		return {"ok": false, "act": "put_down", "reason": "手上沒有拿東西"}
	var c := front_cell()
	var it: Dictionary = items[holding]
	if not in_room(c):
		return {"ok": false, "act": "put_down", "reason": "面前是牆壁，放不下去"}
	if floor_item_at(c, holding) != "":
		return {"ok": false, "act": "put_down", "reason": "面前已經有家具了，放不下去"}
	it.cell = c
	var uid := holding
	holding = ""
	return {"ok": true, "act": "put_down", "uid": uid, "cell": c}


func _push(n: int) -> Dictionary:
	var uid := floor_item_at(front_cell())
	if uid == "":
		return {"ok": false, "act": "push", "reason": "面前沒有家具可以推"}
	var it: Dictionary = items[uid]
	var d: Vector2i = DIRS[gopher_dir]
	var moved := 0
	for i in range(n):
		var next_cell: Vector2i = it.cell + d
		var blocker := ""
		var sz := footprint_size(it.type, it.rot)
		for dx in range(sz.x):
			for dz in range(sz.y):
				var c := next_cell + Vector2i(dx, dz)
				if not in_room(c):
					blocker = "牆壁"
				elif blocker == "" and floor_item_at(c, uid) != "":
					blocker = "其他家具"
		if blocker != "":
			return {"ok": false, "act": "push", "uid": uid, "steps": moved, "reason": "推了 %d 格就推不動了，前面是%s" % [moved, blocker]}
		it.cell = next_cell
		gopher_cell += d
		moved += 1
	return {"ok": true, "act": "push", "uid": uid, "steps": moved}


## 石門：說對密碼才會打開（石門消失，可以走過去）
func _open_gate(code: int) -> Dictionary:
	if lock_gate == "" or not items.has(lock_gate):
		return {"ok": false, "act": "open_gate", "reason": "這裡沒有關著的門"}
	if code != lock_code:
		return {"ok": false, "act": "open_gate", "uid": lock_gate, "reason": "密碼「%d」不對，石門動也不動" % code,
			"hint": "再算一次密碼，數字對了門才會開。"}
	var uid := lock_gate
	items.erase(uid)
	return {"ok": true, "act": "open_gate", "uid": uid}


## A*（四方向）。回傳包含起點與終點的路徑；走不到回傳 []。
func find_path(from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return [from]
	if not walkable(to):
		return []
	var open: Array = [from]
	var came: Dictionary = {}
	var g: Dictionary = {from: 0}
	while not open.is_empty():
		var best_i := 0
		var best_f := 1 << 30
		for i in range(open.size()):
			var c: Vector2i = open[i]
			var f: int = g[c] + abs(c.x - to.x) + abs(c.y - to.y)
			if f < best_f:
				best_f = f
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur == to:
			var path: Array = [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		for dn in DIR_ORDER:
			var nb: Vector2i = cur + DIRS[dn]
			if not walkable(nb):
				continue
			var ng: int = g[cur] + 1
			if not g.has(nb) or ng < g[nb]:
				g[nb] = ng
				came[nb] = cur
				if not (nb in open):
					open.append(nb)
	return []
