class_name BubbleLayer
extends Control
## 2D 對話氣泡，跟著 3D 角色頭頂移動。

var camera_getter: Callable
var bubbles: Array = []  # {actor, panel, until}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_bubble(actor: Node3D, text: String, kind: String = "say", seconds: float = 2.4) -> void:
	# 同一個角色只留一個氣泡；對話一次一句：別人開口，上一句就收起來（「聽不懂」的反應除外，要對照說錯的話）
	for b in bubbles.duplicate():
		if b.actor == actor or (kind != "fail" and is_instance_valid(b.panel)):
			b.panel.queue_free()
			bubbles.erase(b)
	var p := PanelContainer.new()
	var bg := Color("fffdf6")
	var border := UIKit.INK
	if kind == "fail":
		bg = Color("ffe4df")
		border = UIKit.RED
	elif kind == "think":
		bg = Color("eef6ff")
		border = UIKit.BLUE
	var st := UIKit.panel_style(bg, 16, border, 2)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)
	var who: String = actor.get("speaker_name") if actor.get("speaker_name") != null else ""
	if who != "":
		var nl := UIKit.label(who, 13, Color("a0603a"))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nl)
	var l := UIKit.label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF if text.length() < 18 else TextServer.AUTOWRAP_WORD_SMART
	if text.length() >= 18:
		l.custom_minimum_size.x = 280
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	# 氣泡下方的小尾巴（指向說話的角色）
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-9, -2), Vector2(9, -2), Vector2(0, 12)])
	tail.color = bg
	var tail_line := Line2D.new()
	tail_line.points = PackedVector2Array([Vector2(-9, 0), Vector2(0, 12), Vector2(9, 0)])
	tail_line.width = 2.0
	tail_line.default_color = border
	tail.add_child(tail_line)
	p.add_child(tail)
	p.set_meta("tail", tail)
	add_child(p)
	p.scale = Vector2(0.6, 0.6)
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bubbles.append({"actor": actor, "panel": p, "until": Time.get_ticks_msec() + int(seconds * 1000)})


func clear_all() -> void:
	for b in bubbles:
		b.panel.queue_free()
	bubbles.clear()


func _process(_delta: float) -> void:
	var cam: Camera3D = camera_getter.call() if camera_getter.is_valid() else null
	var now := Time.get_ticks_msec()
	for b in bubbles.duplicate():
		if now > b.until or not is_instance_valid(b.actor):
			b.panel.queue_free()
			bubbles.erase(b)
			continue
		if cam == null:
			continue
		var hh: float = b.actor.get("bubble_height") if b.actor.get("bubble_height") != null else 1.35
		var head: Vector3 = b.actor.global_position + Vector3(0, hh, 0)
		if cam.is_position_behind(head):
			b.panel.visible = false
			continue
		b.panel.visible = true
		var sp := cam.unproject_position(head)
		var sz: Vector2 = b.panel.size
		b.panel.pivot_offset = Vector2(sz.x / 2, sz.y)
		b.panel.position = sp - Vector2(sz.x / 2, sz.y + 12)
		var tail: Node2D = b.panel.get_meta("tail")
		tail.position = Vector2(sz.x / 2, sz.y)
