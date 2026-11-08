class_name CameraRig
extends Node3D
## 自由視角：右鍵拖曳旋轉、中鍵拖曳平移、滾輪縮放、Q/E 轉 90 度、WASD 平移。
## follow_target 有值時鏡頭中心會慢慢跟過去（任務演出用）。

var cam: Camera3D
var yaw := deg_to_rad(-35.0)
var pitch := deg_to_rad(-48.0)
var distance := 11.0
var target_yaw := yaw
var target_pitch := pitch
var target_distance := distance
var focus := Vector3(4, 0, 4)
var target_focus := focus
var follow_target: Node3D = null
var home_focus := Vector3(4, 0, 4)
var home_distance := 11.0
var _drag_rotate := false
var _drag_pan := false
## 畫面左右被 UI 擋住時，把焦點往旁邊偏一點（螢幕比例）
var screen_offset := 0.0
## 演出場景要放在螢幕哪一個 x（像素）；< 0 就放正中間。寫程式模式用：兩邊面板中間
var screen_center_x := -1.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	_apply()


func frame_room(w: int, d: int, mult: float = 1.75) -> void:
	home_focus = Vector3(w / 2.0, 0, d / 2.0 + 0.6)
	home_distance = max(w, d) * mult
	reset_view()


func reset_view() -> void:
	target_focus = home_focus
	target_distance = home_distance
	target_yaw = deg_to_rad(-35.0)
	target_pitch = deg_to_rad(-48.0)


func rotate_step(sign_dir: int) -> void:
	target_yaw += sign_dir * PI / 2


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_rotate = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_pan = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(4.0, target_distance * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(maxf(26.0, home_distance * 1.4), target_distance * 1.1)
	elif event is InputEventMouseMotion:
		if _drag_rotate:
			target_yaw -= event.relative.x * 0.008
			target_pitch = clamp(target_pitch - event.relative.y * 0.006, deg_to_rad(-85), deg_to_rad(-12))
		elif _drag_pan:
			_pan(-event.relative.x * 0.012 * target_distance / 10.0, -event.relative.y * 0.012 * target_distance / 10.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: rotate_step(-1)
			KEY_E: rotate_step(1)


func _pan(dx: float, dz: float) -> void:
	follow_target = null
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	target_focus += right * dx + fwd * dz


func _process(delta: float) -> void:
	var focused_ctrl := get_viewport().gui_get_focus_owner()
	if not (focused_ctrl is TextEdit or focused_ctrl is LineEdit):
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W): mv.y -= 1
		if Input.is_key_pressed(KEY_S): mv.y += 1
		if Input.is_key_pressed(KEY_A): mv.x -= 1
		if Input.is_key_pressed(KEY_D): mv.x += 1
		if mv != Vector2.ZERO:
			_pan(mv.x * delta * 6, mv.y * delta * 6)
	if follow_target != null and is_instance_valid(follow_target):
		target_focus = follow_target.global_position
	var k: float = clamp(delta * 6.0, 0, 1)
	yaw = lerp_angle(yaw, target_yaw, k)
	pitch = lerp(pitch, target_pitch, k)
	distance = lerp(distance, target_distance, k)
	focus = focus.lerp(target_focus, k)
	_apply()


func _apply() -> void:
	if cam == null:
		return
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * distance
	cam.position = focus + offset
	cam.look_at(focus + Vector3(0, 0.4, 0), Vector3.UP)
	if screen_center_x >= 0.0:
		# 鏡頭往旁邊平移，讓焦點剛好落在 screen_center_x（不改變遠近和角度，畫面一樣，只是挪位置）
		var vp := get_viewport().get_visible_rect().size
		var half_w := distance * tan(deg_to_rad(cam.fov / 2.0)) * vp.x / maxf(vp.y, 1.0)
		cam.h_offset = (vp.x / 2.0 - screen_center_x) / vp.x * 2.0 * half_w
	else:
		cam.h_offset = screen_offset * distance * 0.35
