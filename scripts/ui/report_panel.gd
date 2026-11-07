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
		title.text = "還差一點點！派派兔的檢查結果"
		title.add_theme_color_override("font_color", UIKit.TEXT_RED)
	box.add_child(title)
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
	scroll.custom_minimum_size = Vector2(0, 240)
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
		txt += "[color=#c9b8a0][font_size=12]%s[/font_size][/color]\n\n" % f.code
	list.text = txt
	# 獎勵
	if rep.passed:
		var rw: Dictionary = task.get("reward", {})
		var msg: String = rw.get("message", "") if first_clear else "這個任務之前已經完成過了，獎勵已經在收藏裡囉。"
		if rep.stars < 3:
			msg += "\n（拿到三顆星的方法：照任務單的規定寫法再挑戰一次！）"
		var rl := UIKit.label(msg, 18, Color("8a5a1a"))
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(rl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.add_child(UIKit.button("回去修改程式", func(): retry_pressed.emit()))
	if rep.passed:
		var b := UIKit.primary(UIKit.button("收下獎勵、回家擺設", func(): accept_pressed.emit()))
		b.add_theme_font_size_override("font_size", 19)
		row.add_child(b)
	box.add_child(row)
	visible = true
