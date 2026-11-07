class_name ReportPanel
extends Control
## 交件後的評估報告：嚴格列出所有偏差，依評分政策標成「不通過／扣星／提醒」。

signal retry_pressed
signal accept_pressed

var box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.2, 0.12, 0.05, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("fff8ec"), 20, UIKit.INK, 3))
	center.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)


func show_report(task: Dictionary, rep: Dictionary, first_clear: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	var title := UIKit.label("", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if rep.passed:
		title.text = "任務完成！ " + "★".repeat(rep.stars) + "☆".repeat(3 - rep.stars)
		title.add_theme_color_override("font_color", UIKit.TEXT_WARN)
	else:
		title.text = "還差一點點！%s的檢查結果" % RoomView.NAMES.get(task.get("npc", "wolf"), "派派狼")
		title.add_theme_color_override("font_color", UIKit.TEXT_RED)
	box.add_child(title)
	if rep.passed and first_clear:
		_add_stamp(title)
	# 測資結果
	var cases_row := HBoxContainer.new()
	cases_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cases_row.add_theme_constant_override("separation", 8)
	for c in rep.cases:
		var chip := UIKit.label(("✓ " if c.ok else "× ") + c.name, 15, UIKit.TEXT_GREEN if c.ok else UIKit.TEXT_RED)
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		var st := UIKit.panel_style(Color("eef8e8") if c.ok else Color("ffe9e4"), 10, UIKit.GREEN if c.ok else UIKit.RED, 1)
		st.shadow_size = 0
		chip.add_theme_stylebox_override("normal", st)
		cases_row.add_child(chip)
	box.add_child(cases_row)
	# 評估清單
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := RichTextLabel.new()
	list.bbcode_enabled = true
	list.fit_content = true
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("normal_font_size", 16)
	list.add_theme_font_size_override("bold_font_size", 16)
	scroll.add_child(list)
	var txt := ""
	if rep.findings.is_empty():
		txt = "[color=#3d7a3d]✓ 全部符合任務單！寫法也完全正確。[/color]"
	var order := {"block": 0, "warn": 1, "info": 2}
	var fs: Array = rep.findings.duplicate()
	fs.sort_custom(func(a, b): return order[a.severity] < order[b.severity])
	for f in fs:
		var icon := "[color=#b8473f]× 不通過[/color]"
		if f.severity == "warn":
			icon = "[color=#8f5f12]▲ 扣一顆星[/color]"
		elif f.severity == "info":
			icon = "[color=#3a75b0]● 提醒[/color]"
		var case_tag := ("  [color=#8a6a50]〔%s〕[/color]" % UIKit.esc(f.case)) if f.case != "" else ""
		txt += "%s%s\n[b]%s[/b]\n" % [icon, case_tag, UIKit.esc(f.message)]
		if f.get("hint", "") != "":
			txt += "[color=#8a6a50]提示：%s[/color]\n" % UIKit.esc(f.hint)
		txt += "\n"
	list.text = txt.strip_edges()
	_fit_scroll.call_deferred(scroll, list)
	# 獎勵
	if rep.passed:
		var rw: Dictionary = task.get("reward", {})
		var msg: String = rw.get("message", "") if first_clear else "這個任務之前已經完成過了，獎勵已經在收藏裡囉。"
		if rep.stars < 3:
			msg += "\n（拿到三顆星的方法：照任務單的規定寫法再挑戰一次！）"
		var ftype: String = rw.get("furniture", "")
		if first_clear and ftype != "":
			box.add_child(_reward_preview(ftype))
		var rl := UIKit.label(msg, 18, Color("8a5a1a"))
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(rl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var back := UIKit.focusable(UIKit.button("回去修改程式", func(): retry_pressed.emit(), "也可以按 Esc"))
	row.add_child(back)
	var main_btn: Button = back
	if rep.passed:
		var b := UIKit.focusable(UIKit.primary(UIKit.button("收下獎勵、回家擺設", func(): accept_pressed.emit())))
		b.add_theme_font_size_override("font_size", 19)
		row.add_child(b)
		main_btn = b
	box.add_child(row)
	visible = true
	main_btn.grab_focus.call_deferred()  # 按 Enter 就是主要的那個選擇


## 「完成！」印章：從大大的蓋下來（0.25 秒）
func _add_stamp(title: Label) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	title.add_child(holder)
	var l := UIKit.label("完成！", 22, Color("2f5f8f"))
	l.add_theme_font_override("font", UIKit.font_bold())
	var st := UIKit.panel_style(Color("dbe4ee"), 10, Color("3a75b0"), 3)
	st.shadow_size = 0
	l.add_theme_stylebox_override("normal", st)
	holder.add_child(l)
	l.position = Vector2(-120, -6)
	l.rotation = deg_to_rad(-12)
	await get_tree().process_frame
	if not is_instance_valid(l):
		return
	l.pivot_offset = l.size / 2
	if UIKit.reduce_motion:
		return
	l.scale = Vector2(1.4, 1.4)
	l.modulate.a = 0.0
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)


## 獎勵家具的小展示台：獨立的 3D 小世界，家具慢慢轉
func _reward_preview(ftype: String) -> Control:
	var center := CenterContainer.new()
	var frame := PanelContainer.new()
	var fst := UIKit.panel_style(Color("fff1d6"), 14, UIKit.INK, 2)
	fst.shadow_size = 0
	fst.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", fst)
	center.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(200, 130)
	frame.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var node := Models.furniture(ftype)
	pivot.add_child(node)
	# 依家具大小擺鏡頭
	var box := _mesh_aabb(node, Transform3D.IDENTITY)
	node.position = -box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.2)
	var cam := Camera3D.new()
	cam.fov = 35
	vp.add_child(cam)
	var cpos := Vector3(0, r * 0.9, r * 3.0)
	cam.transform = Transform3D(Basis.looking_at(-cpos), cpos)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1d6")
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d6")
	sun.rotation_degrees = Vector3(-45, -30, 0)
	vp.add_child(sun)
	pivot.rotation_degrees.y = -30
	if not UIKit.reduce_motion:
		var tw := pivot.create_tween().set_loops()
		tw.tween_property(pivot, "rotation_degrees:y", 330.0, 8.0).from(-30.0)
	return center


static func _mesh_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is GeometryInstance3D:  # 只算看得到的模型（燈光的範圍不算）
		var b: AABB = t * (n as GeometryInstance3D).get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _mesh_aabb(c, t)
		if cb.size == Vector3.ZERO:
			continue
		out = cb if first else out.merge(cb)
		first = false
	return out


## 清單多高，捲動區就多高（最多 360，超過才捲動），不會留一大片空白
func _fit_scroll(scroll: ScrollContainer, list: RichTextLabel) -> void:
	if not is_instance_valid(list):
		return
	await get_tree().process_frame
	if is_instance_valid(list):
		scroll.custom_minimum_size.y = minf(list.get_content_height() + 4, 360)
