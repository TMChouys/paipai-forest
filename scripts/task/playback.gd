class_name Playback
extends Node
## 把 TaskRunner 算好的 timeline 一步一步演出來：亮行、更新變數、輸出、角色動作。
## 支援暫停／繼續、單步（一次一行）、速度。

signal finished(completed: bool)

var view: RoomView
var panel: TaskPanel
var speed := 1.0
var paused := false
var step_mode := false
var running := false
var cancelled := false
var demo := false
var highlight := true


func cancel() -> void:
	cancelled = true
	paused = false


func toggle_pause() -> void:
	if not running:
		return
	step_mode = false
	paused = not paused


func step() -> void:
	step_mode = true
	paused = false


func play(timeline: Array) -> bool:
	running = true
	cancelled = false
	var seen_line := false
	for ev in timeline:
		if cancelled:
			break
		if ev.type == "line" and step_mode and seen_line:
			paused = true
		while paused and not cancelled:
			if panel:
				panel.set_running(true, true)
			await get_tree().process_frame
		if panel:
			panel.set_running(true, false)
		if cancelled:
			break
		match ev.type:
			"line":
				seen_line = true
				if panel and highlight:
					panel.highlight_line(ev.line)
					panel.set_vars(ev.vars)
				await get_tree().create_timer(0.2 / speed).timeout
			"print":
				if panel:
					panel.log_output(ev.text, demo)
			"input":
				# 像真的終端機：問題後面接著輸入的回答
				if panel:
					panel.log_input(ev.prompt, ev.value, demo)
			"action":
				if panel and ev.result.ok and ev.result.get("act", "") == "say" and ev.result.who != "gopher":
					panel.log_system("%s：%s" % [TaskRunner.NAMES.get(ev.result.who, ""), ev.result.text], "#d8c3a5")
				await view.play_result(ev.result, speed)
				if not ev.result.ok and panel:
					var who := "" if ev.result.get("act", "") == "dlg_fail" else "派派鼠："
					panel.log_system(who + ev.result.get("reason", ""), "#ff8a80")
					if ev.result.get("hint", "") != "":
						panel.log_system("提示：%s" % ev.result.hint, "#ffd59a")
					if highlight:
						panel.mark_error(ev.line)
			"call":
				if panel:
					panel.log_system("呼叫 %s%s" % [ev.name, str(ev.args)], "#9fd3e6")
			"error":
				if panel:
					if highlight:
						panel.log_error(ev.error)
					else:
						panel.log_system("示範發生錯誤：" + ev.error.message, "#ff8a80")
				view.gopher.say("咦？程式出錯了…", "fail")
				await view.gopher.confused()
	running = false
	step_mode = false
	paused = false
	var ok := not cancelled
	finished.emit(ok)
	return ok
