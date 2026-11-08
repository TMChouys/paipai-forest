class_name LessonStage
extends PanelContainer
## 認識世界課本裡的小舞台：慢慢館長說故事（①～③），派派鼠、派派狼、派派兔把題目的情境演出來（④）。
## play([[角色, 台詞, 動作], …])：一句一句演；動作 hop／happy／confused／think 可省略。
## 派派鼠不會說話：它說的都是程式印出來的結果。

const SPOTS := {"turtle": Vector3(-2.7, 0, -0.3), "wolf": Vector3(-1.2, 0, 0.0), "gopher": Vector3(0.1, 0, 0.3), "rabbit": Vector3(1.4, 0, 0.0)}
const NAMES := {"turtle": "慢慢館長", "gopher": "派派鼠", "wolf": "派派狼", "rabbit": "派派兔"}
const BUBBLE_H := {"turtle": 1.3, "gopher": 1.15, "wolf": 1.45, "rabbit": 1.45}

var vp: SubViewport
var cam: Camera3D
var bubbles: BubbleLayer
var actors: Dictionary = {}
var _gen := 0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 215)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.panel_style(Color("dcefd2"), 12, UIKit.INK, 2)
	st.shadow_size = 0
	st.set_content_margin_all(2)
	add_theme_stylebox_override("panel", st)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	_build_world()
	bubbles = BubbleLayer.new()
	bubbles.camera_getter = func(): return cam
	add_child(bubbles)
	resized.connect(func(): bubbles.clamp_rect = Rect2(Vector2(6, 4), size - Vector2(12, 8)))


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cfe8f2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff4e0")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 1.5, 4.6)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	# 格子梅花地板（跟野外地圖一樣）
	var tile := BoxMesh.new()
	tile.size = Vector3(0.96, 0.1, 0.96)
	var mats := [_mat(Color("eadcae")), _mat(Color("d8c48c"))]
	for x in range(-5, 5):
		for z in range(-3, 2):
			var m := MeshInstance3D.new()
			m.mesh = tile
			m.material_override = mats[(x + z) & 1]
			m.position = Vector3(x + 0.5, -0.05, z + 0.5)
			vp.add_child(m)
	var grass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	grass.mesh = pm
	grass.material_override = _mat(Color("a8cf8a"))
	grass.position.y = -0.1
	vp.add_child(grass)
	# 遠處的小樹叢
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.35, 0.7)
		sm.radius = r
		sm.height = r * 1.7
		b.mesh = sm
		b.material_override = _mat(Color("7fb069").lerp(Color("5f9a55"), rng.randf()))
		b.position = Vector3(-7 + i + rng.randf_range(-0.3, 0.3), r * 0.6, -3.6 - rng.randf_range(0, 1.2))
		vp.add_child(b)
	for who in SPOTS:
		var a := GopherActor.new()
		vp.add_child(a)
		a.setup(Models.character(who))
		a.speaker_name = NAMES[who]
		a.bubble_height = BUBBLE_H[who]
		a.position = SPOTS[who]
		a.face("S")
		a.model.rotation.y = a.target_yaw
		a.bubble_requested.connect(func(actor, text, kind): bubbles.show_bubble(actor, text, kind, 600.0))
		actors[who] = a


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # 地板、草地用固定的顏色，不會被光照洗白
	return m


## 一句一句演出來；換頁或再呼叫一次就停掉上一段
func play(lines: Array) -> void:
	_gen += 1
	var g := _gen
	bubbles.clear_all()
	for ln in lines:
		if g != _gen or not is_inside_tree() or not visible:
			return
		var who: String = ln[0]
		var text: String = ln[1]
		var act: String = ln[2] if ln.size() > 2 else ""
		var a: GopherActor = actors.get(who)
		if a == null:
			continue
		match act:
			"hop":
				a.hop(0.2)
			"happy":
				a.happy()
			"confused":
				a.confused()
		a.say(text, "think" if act == "think" else "say")
		await get_tree().create_timer(maxf(1.7, 0.9 + text.length() * 0.1)).timeout


func stop() -> void:
	_gen += 1
	if bubbles:
		bubbles.clear_all()


func react(who: String, how: String) -> void:
	var a: GopherActor = actors.get(who)
	if a == null:
		return
	if how == "happy":
		a.happy()
	elif how == "confused":
		a.confused()
	else:
		a.hop(0.2)
