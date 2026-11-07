extends SceneTree
## 開發用：找派派狼尾巴的頂點（身體後面、貼圖顏色深的那一塊）


func _init() -> void:
	var inst: Node3D = (load("res://models/wolf/wolf_rigged.glb") as PackedScene).instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in mis:
		var mesh := mi.mesh
		print("mesh ", mi.name, " surfaces ", mesh.get_surface_count(), " aabb ", mesh.get_aabb())
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			var img: Image = null
			if mat and mat.albedo_texture:
				img = mat.albedo_texture.get_image()
				if img.is_compressed():
					img.decompress()
				print(" surf ", si, " mat ", mat.resource_name, " tex ", img.get_size())
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			print("  verts ", v.size())
			if img == null:
				continue
			# 依 z 分層統計後面的顏色
			var zmin := 1e9
			for p in v:
				zmin = minf(zmin, p.z)
			print("  zmin ", zmin)
			var buckets := {}
			for i in v.size():
				var p := v[i]
				var c := img.get_pixelv(Vector2i(uv[i] * Vector2(img.get_size())).clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE))
				var key := "z%.2f_y%.2f" % [snappedf(p.z, 0.05), snappedf(p.y, 0.1)]
				if p.z < zmin + 0.25:
					if not buckets.has(key):
						buckets[key] = [0, 0.0]
					buckets[key][0] += 1
					buckets[key][1] += c.get_luminance()
			var ks := buckets.keys()
			ks.sort()
			for k in ks:
				print("   ", k, " n=", buckets[k][0], " lum=", snappedf(buckets[k][1] / buckets[k][0], 0.01))
	quit()
