extends SceneTree
## 角色近照：godot --path . --resolution 1280x720 --script res://tools/preview_chars.gd -- --out=C:/x.png [--anim=walk] [--yaw=30]

func _init() -> void:
	var out := "user://chars.png"
	var anim_name := "idle"
	var face_expr := ""
	var yaw := 25.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--anim="): anim_name = a.substr(7)
		if a.begins_with("--yaw="): yaw = float(a.substr(6))
		if a.begins_with("--face="): face_expr = a.substr(7)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("fbf3e3")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1e0")
	e.ambient_light_energy = 0.42
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	floor_mi.mesh = pm
	floor_mi.material_override = Models.mat(Color("e2c59a"), false)
	world.add_child(floor_mi)
	var _seek := 0.3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seek="):
			_seek = float(a.substr(7))
	var solo := "--solo" in OS.get_cmdline_user_args()
	var lineup := "--lineup" in OS.get_cmdline_user_args()
	var chars: Array = [Models.gopher()] if solo else [Models.gopher(), _plain("res://models/cozy/Otter.glb")]
	var x := 0.0 if solo else -0.7
	if "--chief" in OS.get_cmdline_user_args():
		chars = [Models.village_chief()]
	elif "--pair" in OS.get_cmdline_user_args():
		chars = [Models.gopher(), Models.village_chief()]
	elif "--trio" in OS.get_cmdline_user_args():
		chars = [Models.character("wolf"), Models.gopher(), Models.character("rabbit")]
		x = -1.2
	if lineup:
		chars = [Anthro.build("chief_polarbear", "A", 1.05), Anthro.build("chief_raccoon", "B", 1.0), Models.gopher(), Anthro.build("neighbor_redpanda", "C", 0.95), Anthro.build("neighbor_fox", "D", 0.95)]
		x = -2.4
	for c in chars:
		var holder := Node3D.new()
		holder.add_child(c)
		holder.position = Vector3(x, 0, 0)
		holder.rotation_degrees.y = yaw
		world.add_child(holder)
		if face_expr != "" and c.has_meta("face"):
			(c.get_meta("face") as ShaderMaterial).set_shader_parameter("face", FaceArt.texture(face_expr))
		var ap: AnimationPlayer = c.get_meta("anim") if c.has_meta("anim") else null
		if ap == null:
			var found: Array = c.find_children("*", "AnimationPlayer", true, false)
			ap = found[0] if not found.is_empty() else null
		if ap and ap.has_animation(anim_name):
			ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			ap.play(anim_name)
			ap.seek(_seek, true)
		x += 1.2 if lineup else 1.4
	var cam := Camera3D.new()
	cam.fov = 30
	world.add_child(cam)
	if lineup:
		cam.look_at_from_position(Vector3(0, 1.3, 6.2), Vector3(0, 0.5, 0))
	elif "--low" in OS.get_cmdline_user_args():
		cam.look_at_from_position(Vector3(0, 0.12, 3.4), Vector3(0, 0.3, 0))
	elif "--close" in OS.get_cmdline_user_args():
		cam.look_at_from_position(Vector3(0, 0.78, 1.5), Vector3(0, 0.66, 0))
	elif solo:
		cam.look_at_from_position(Vector3(0, 0.75, 2.4), Vector3(0, 0.45, 0))
	else:
		cam.look_at_from_position(Vector3(0, 0.95, 3.4), Vector3(0, 0.4, 0))
	for i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()


func _plain(path: String) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.scale = Vector3.ONE * (0.85 / 1.7)
	return n
