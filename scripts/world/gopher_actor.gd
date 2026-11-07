class_name GopherActor
extends Node3D
## 角色演員：包住模型，負責走路搖擺、轉向、搬東西、困惑、開心等程序動畫。

signal bubble_requested(actor: Node3D, text: String, kind: String)

## 氣泡上顯示的名字（派派鼠／派派狼／派派兔）
var speaker_name := ""
## 氣泡離地的高度（耳朵高的角色要高一點）
var bubble_height := 1.35

const DIR_YAW := {"S": 0.0, "N": PI, "E": PI / 2, "W": -PI / 2}

var model: Node3D
var body: Node3D
var head: Node3D
var foot_l: Node3D
var foot_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var carry_anchor: Node3D
var carried: Node3D = null
var dir := "S"
var moving := false
var pushing := false
var t := 0.0
var walk_phase := 0.0
var speed_scale := 1.0
var target_yaw := 0.0
var sitting := false


func setup(m: Node3D) -> void:
	model = m
	add_child(model)
	body = model.get_node_or_null("Body")
	head = model.find_child("Head", true, false)
	foot_l = model.find_child("FootL", true, false)
	foot_r = model.find_child("FootR", true, false)
	arm_l = model.find_child("ArmL", true, false)
	arm_r = model.find_child("ArmR", true, false)
	for f in [foot_l, foot_r]:
		if f:
			_foot_base[f] = f.position
			# 腳的父節點可能被縮放過（GLB），把擺動距離換算回模型單位
			var sc: float = Models._rel_xform(f.get_parent() as Node3D, model).basis.get_scale().x if f.get_parent() != model else 1.0
			_foot_unit[f] = 1.0 / maxf(sc, 0.0001)
	carry_anchor = Node3D.new()
	carry_anchor.position = Vector3(0, 1.0, 0.05)
	model.add_child(carry_anchor)
	face_mat = model.get_meta("face") if model.has_meta("face") else null
	_blink_at = randf_range(1.5, 4.0)
	anim = model.get_meta("anim") if model.has_meta("anim") else null
	if anim:
		anthro = model.has_meta("anthro")
		if anthro:
			# 獸人：家具抱在胸前，走路時雙手維持捧著的姿勢
			carry_anchor.position = Vector3(0, 0.36, 0.34)
			var skel: Skeleton3D = model.get_meta("skeleton")
			if anim.has_animation("holding-both"):
				arm_hold = ArmHold.from_animation(skel, anim.get_animation("holding-both"), ["arm-left", "arm-right"])
				skel.add_child(arm_hold)
		else:
			carry_anchor.position = Vector3(0, 1.0, 0.0)


## 有骨架動畫的模型：Cozy Animals（idle / walk / gesture）或獸人身體（Kenney Mini Characters）
var anim: AnimationPlayer = null
var anthro := false
var arm_hold: ArmHold = null
var _gesturing := false

## 2D 臉（FaceArt）：表情、眨眼、說話嘴型
var face_mat: ShaderMaterial = null
var _face_expr := "normal"
var _face_until := 0.0
var _talk_until := 0.0
var _blink_at := 0.0
var _shown_face := ""


## 換表情；dur > 0 時幾秒後回到 normal
func set_face(expr: String, dur: float = 0.0) -> void:
	_face_expr = expr
	_face_until = t + dur / max(speed_scale, 0.01) if dur > 0.0 else 0.0


func _update_face() -> void:
	if face_mat == null:
		return
	if _face_until > 0.0 and t > _face_until:
		_face_expr = "normal"
		_face_until = 0.0
	var show := _face_expr
	if show == "normal":
		if t < _talk_until:
			show = "talk" if int(t * 7.0) % 2 == 0 else "normal"
		elif t > _blink_at:
			show = "blink"
			if t > _blink_at + 0.13:
				_blink_at = t + randf_range(2.0, 5.0)
	if show != _shown_face:
		_shown_face = show
		face_mat.set_shader_parameter("face", FaceArt.texture(show))
var _seated := false


func _update_anim() -> void:
	if anim == null or _gesturing:
		return
	var want := "walk" if moving else "idle"
	if anthro:
		if _seated:
			want = "idle"  # sit 動畫會把整個身體往下壓（是給別的座位高度做的），坐椅子用待機姿勢
		elif carried != null and not moving:
			want = "holding-both"
		# 抱著或推著走：走路動畫＋雙手固定
		if arm_hold:
			arm_hold.active = moving and (carried != null or pushing)
	if anim.current_animation != want and anim.has_animation(want):
		anim.play(want, 0.15)
	# 走一格約 0.32 秒
	anim.speed_scale = ((1.6 if anthro else 1.25) * speed_scale) if moving else 1.0


## 播一次性的動作（揮手、點頭、搖頭、撿東西…），播完回到待機／走路
func play_once(names: Array, max_time: float = 1.5) -> void:
	if anim == null:
		return
	for n in names:
		if anim.has_animation(n):
			_gesturing = true
			anim.play(n, 0.1)
			anim.speed_scale = speed_scale
			var t0 := Time.get_ticks_msec()
			var limit: float = min(anim.get_animation(n).length / max(speed_scale, 0.01), max_time / max(speed_scale, 0.01))
			while anim.current_animation == n and (Time.get_ticks_msec() - t0) / 1000.0 < limit:
				await get_tree().process_frame
			_gesturing = false
			return


func play_gesture() -> void:
	await play_once(["emote-yes", "interact-right", "gesture"])


func set_seated(v: bool) -> void:
	_seated = v


var _foot_base: Dictionary = {}
var _foot_unit: Dictionary = {}


func _foot_anim(f: Node3D, phase: float, delta: float) -> void:
	if f == null:
		return
	var base: Vector3 = _foot_base[f]
	var u: float = _foot_unit[f]
	if moving:
		f.position = base + Vector3(0, max(0.0, phase) * 0.05, phase * 0.08) * u
	else:
		f.position = f.position.lerp(base, delta * 10)


func _process(delta: float) -> void:
	t += delta
	_update_face()
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clamp(delta * 12.0 * speed_scale, 0, 1))
	if anim:
		# 骨架動畫負責走路（獸人模型沒有 Body 節點，所以要先處理，不然走路動畫永遠不會播）
		_update_anim()
		if body != null:
			body.rotation.x = lerp(body.rotation.x, 0.18 if pushing else 0.0, delta * 8)
		return
	if body == null:
		return
	if moving:
		walk_phase += delta * 11.0 * speed_scale
		var s := sin(walk_phase)
		body.position.y = abs(s) * 0.06
		body.rotation.z = s * 0.12
		body.rotation.x = 0.25 if pushing else 0.05
		_foot_anim(foot_l, s, delta)
		_foot_anim(foot_r, -s, delta)
	else:
		var b := sin(t * 2.2)
		body.position.y = lerp(body.position.y, 0.0, delta * 8)
		body.rotation.z = lerp(body.rotation.z, 0.0, delta * 8)
		body.rotation.x = lerp(body.rotation.x, 0.0, delta * 8)
		body.scale = Vector3(1.0 - b * 0.012, 1.0 + b * 0.02, 1.0 - b * 0.012)
		_foot_anim(foot_l, 0.0, delta)
		_foot_anim(foot_r, 0.0, delta)
	# 搬東西時手舉高
	var arm_target := -150.0 if carried != null else (-70.0 if pushing else 0.0)
	for arm in [arm_l, arm_r]:
		if arm:
			arm.rotation_degrees.x = lerp(arm.rotation_degrees.x, arm_target, delta * 10)


static func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, 0, c.y + 0.5)


func face(d: String) -> void:
	dir = d
	target_yaw = DIR_YAW.get(d, 0.0)


func face_vector(v: Vector3) -> void:
	if v.length() > 0.001:
		target_yaw = atan2(v.x, v.z)


func walk_path(cells: Array, extra: Node3D = null) -> void:
	if cells.size() < 2:
		return
	moving = true
	for i in range(1, cells.size()):
		var to := cell_pos(cells[i])
		face_vector(to - position)
		var tw := create_tween()
		tw.tween_property(self, "position", to, 0.32 / speed_scale)
		if extra != null:
			var off: Vector3 = extra.position - position
			tw.parallel().tween_property(extra, "position", to + off, 0.32 / speed_scale)
		await tw.finished
	moving = false


## 直直走到某個點（不在格子上的角色用，例如從森林走到門口），到了轉向 facing
func walk_to_point(to: Vector3, speed_mult: float = 1.0, facing: String = "N") -> void:
	to.y = position.y
	moving = true
	face_vector(to - position)
	var tw := create_tween()
	tw.tween_property(self, "position", to, position.distance_to(to) * 0.34 / (speed_scale * speed_mult))
	await tw.finished
	moving = false
	face(facing)


func turn_to(d: String) -> void:
	face(d)
	await get_tree().create_timer(0.25 / speed_scale).timeout


func pick(node: Node3D) -> void:
	if anthro:
		await play_once(["pick-up"], 0.7)
	else:
		await hop(0.08)
	carried = node
	var gt := node.global_transform
	node.get_parent().remove_child(node)
	carry_anchor.add_child(node)
	node.global_transform = gt
	var tw := create_tween()
	tw.tween_property(node, "position", Vector3(0, 0.0, 0.0) if anthro else Vector3(0, 0.05, 0.1), 0.25 / speed_scale)
	tw.parallel().tween_property(node, "scale", Vector3.ONE * (0.5 if anthro else 0.6), 0.25 / speed_scale)
	await tw.finished


## 把手上的家具放到 world_pos，回傳該節點（呼叫端要把它掛回房間）
func drop(new_parent: Node3D, world_pos: Vector3) -> Node3D:
	var node := carried
	if node == null:
		return null
	if anthro:
		play_once(["pick-up"], 0.6)
	carried = null
	var gt := node.global_transform
	carry_anchor.remove_child(node)
	new_parent.add_child(node)
	node.global_transform = gt
	var tw := create_tween()
	tw.tween_property(node, "position", world_pos, 0.3 / speed_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "scale", Vector3.ONE, 0.3 / speed_scale)
	await tw.finished
	return node


func hop(h: float = 0.25) -> void:
	if body == null:
		return
	var tw := create_tween()
	tw.tween_property(body, "position:y", h, 0.12 / speed_scale).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position:y", 0.0, 0.14 / speed_scale).set_ease(Tween.EASE_IN)
	await tw.finished


func confused() -> void:
	set_face("confused", 2.2)
	if anthro and anim and anim.has_animation("emote-no"):
		await play_once(["emote-no"], 1.2)
		return
	if head == null:
		return
	var tw := create_tween()
	tw.tween_property(head, "rotation:z", 0.35, 0.2 / speed_scale)
	tw.tween_interval(0.5 / speed_scale)
	tw.tween_property(head, "rotation:z", -0.25, 0.2 / speed_scale)
	tw.tween_interval(0.3 / speed_scale)
	tw.tween_property(head, "rotation:z", 0.0, 0.2 / speed_scale)
	await tw.finished


func happy() -> void:
	set_face("happy", 2.0)
	if anim and (anim.has_animation("gesture") or anim.has_animation("emote-yes")):
		hop(0.15)
		await play_gesture()
		return
	await hop(0.3)
	await hop(0.2)


func say(text: String, kind: String = "say") -> void:
	_talk_until = t + clampf(text.length() * 0.08, 0.6, 2.0)
	bubble_requested.emit(self, text, kind)
