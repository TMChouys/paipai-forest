extends SceneTree
## 看任何 GLB 的四面（正、右、背、左）：godot --path . --resolution 1280x480 --script res://tools/view_model.gd -- --in=res://x.glb --out=C:/x.png

func _init() -> void:
	var src := ""
	var out := "user://view.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="): src = a.substr(5)
		if a.begins_with("--out="): out = a.substr(6)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("fbf3e3")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff1e0")
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -20, 0)
	world.add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-40, 160, 0)
	back.light_energy = 0.5
	world.add_child(back)
	var aabb := AABB()
	for k in 4:
		var inst: Node3D = (load(src) as PackedScene).instantiate()
		world.add_child(inst)
		inst.rotation_degrees.y = 90.0 * k
		var first := true
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			var b := mi.get_aabb()
			if k == 0:
				print("MESH ", mi.name, " ", b, " surfaces ", mi.mesh.get_surface_count())
			aabb = b if first else aabb.merge(b)
			first = false
		if k == 0:
			print("SKEL ", inst.find_children("*", "Skeleton3D", true, false).size(), " ANIM ", inst.find_children("*", "AnimationPlayer", true, false).size(), " AABB ", aabb)
		inst.position.x = (k - 1.5) * aabb.size.x * 1.25 - aabb.get_center().x
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = aabb.size.y * 1.15
	cam.position = Vector3(0, aabb.get_center().y, 10)
	world.add_child(cam)
	cam.make_current()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out)
	quit()
