extends SceneTree
## 開發用：每個任務的標準答案都要能拿滿分（通過、沒有扣分）；qa_wrong 的錯誤答案不能拿滿分。
## godot --headless --path . --script res://tools/verify_tasks.gd


func _init() -> void:
	var bad := 0
	for t in TaskRunner.list_tasks():
		var rep := TaskChecker.evaluate(t, t.reference)
		var ok: bool = rep.passed and int(rep.warns) == 0
		print("%s %s  stars=%d warns=%d" % ["OK  " if ok else "FAIL", t.id, rep.stars, rep.warns])
		if not ok:
			bad += 1
			for f in rep.findings:
				print("     - [%s] %s %s" % [f.severity, f.message, f.get("hint", "")])
		# qa_wrong：故意寫錯的答案，一定不能拿滿分
		for w in t.get("qa_wrong", []):
			var wr := TaskChecker.evaluate(t, w)
			var full: bool = wr.passed and int(wr.warns) == 0
			print("     wrong %s stars=%d warns=%d" % ["LEAK" if full else "ok  ", wr.stars, wr.warns])
			if full:
				bad += 1
	print("done, failed: ", bad)
	quit()
