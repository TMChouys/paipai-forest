# 慢慢館長 turtle_2（使用者的新模型）暫時補背後：原檔背後是一整片平面，
# 先借 fix_turtle.py 的龜殼產生器，在背上補一個圓頂大龜殼（材質 PinShell，上骨架時整片跟身體走）。
# 正式模型做好就換掉，這個腳本可以刪。
# 用法：blender -b --factory-startup --python tools/blender/patch_turtle2_back.py -- <turtle_2.glb> <out.glb>
import os, sys
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fix_turtle.py"), encoding="utf-8").read()
head = src[:src.index("# ================= 1. 貼圖")]
shell = src[src.index("# ================= 2. 新龜殼"):src.index("# ================= 3. 新披風")]
# turtle_2 的背平面在 y = 0.35，殼的輪廓（從背後看）寬 ±0.84、高 z -0.7..0.93
shell = shell.replace('SC = Vector((0.0, 0.15, 0.10))', 'SC = Vector((0.0, 0.25, 0.14))')
shell = shell.replace('SR = Vector((0.76, 0.64, 0.58))', 'SR = Vector((0.80, 0.30, 0.76))')
assert 'SC = Vector((0.0, 0.25, 0.14))' in shell and 'SR = Vector((0.80, 0.30, 0.76))' in shell
# 顏色配合 turtle_2 側面原本的深咖啡色殼
for a, b in [("SHELL = np.array([0.64, 0.45, 0.27])", "SHELL = np.array([0.47, 0.33, 0.21])"),
             ("SHELL_LIGHT = np.array([0.76, 0.56, 0.34])", "SHELL_LIGHT = np.array([0.58, 0.42, 0.28])"),
             ("SHELL_GROOVE = np.array([0.36, 0.23, 0.13])", "SHELL_GROOVE = np.array([0.26, 0.17, 0.10])"),
             ("SHELL_RIM = np.array([0.55, 0.38, 0.22])", "SHELL_RIM = np.array([0.42, 0.29, 0.18])")]:
    assert a in head, a
    head = head.replace(a, b)
g = {"__name__": "patch"}
exec(compile(head + shell + '''
for m in body.data.materials:
    m.name = "Body"
# 龜殼下面的披風下擺：原本是平的，補一片往後微微鼓起的布（上緣塞進殼裡），下襬一條金邊
def flat_material(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m
NU2, NV2 = 40, 16
Z_TOP, Z_BOT, XW2 = -0.42, -0.985, 0.69
cape = bmesh.new()
grid = []
for j in range(NV2 + 1):
    t = j / NV2                       # 0 上緣 → 1 下襬
    z = Z_TOP + (Z_BOT - Z_TOP) * t
    row = []
    for i in range(NU2 + 1):
        u = -1 + 2 * i / NU2
        x = u * (XW2 + 0.04 * t)
        bulge = (0.05 + 0.11 * t ** 0.8) * max(0.0, 1 - u * u) ** 0.6
        fold = 0.012 * math.sin(u * 9.0) * t        # 一點點布的皺褶
        row.append(cape.verts.new((x, 0.345 + bulge + fold, z)))
    grid.append(row)
hem_faces = []
for j in range(NV2):
    for i in range(NU2):
        f = cape.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
        f.material_index = 1 if j >= NV2 - 1 else 0
bmesh.ops.recalc_face_normals(cape, faces=cape.faces)
for f in cape.faces:                 # 法線朝後（+Y）
    if f.normal.y < 0:
        f.normal_flip()
cape_me = bpy.data.meshes.new("cape2"); cape.to_mesh(cape_me); cape.free()
cape_me.materials.append(flat_material("PinCape", (0.27, 0.15, 0.33)))
cape_me.materials.append(flat_material("PinHem", (0.80, 0.64, 0.36), 0.6))
for p in cape_me.polygons:
    p.use_smooth = True
cape_me.uv_layers.new(name="UVMap")
cape_ob = bpy.data.objects.new("cape2", cape_me); bpy.context.collection.objects.link(cape_ob)
bpy.ops.object.select_all(action='DESELECT')
for o in (body, shell_ob, cape_ob):
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
print("VERTS", len(body.data.vertices), "MATS", [m.name for m in body.data.materials])
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_image_format='JPEG',
                          export_jpeg_quality=92, export_yup=True, use_selection=False)
print("EXPORTED", OUT)
''', "patch_turtle2_back", "exec"), g)
