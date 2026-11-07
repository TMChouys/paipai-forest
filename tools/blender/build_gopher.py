# 土撥鼠獸人：以 Kenney Mini Characters 的人型骨架（含全部動畫）為基礎，
# 在 Blender 裡用程式捏出參考圖風格的胖胖土撥鼠（綠背心＋斜背包），每個部件綁到一根骨頭。
# 用法：blender -b --factory-startup --python tools/blender/build_gopher.py -- <kenney_glb> <out_glb> [preview_dir]
# Blender 座標：Z 向上，角色面向 -Y。骨架：髖 0.176、肩 0.288、脖子 0.343。
import bpy, bmesh, sys, math, os
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREVIEW = args[2] if len(args) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for o in list(bpy.data.objects):
    if o.type == 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
arm.name = "Gopher"
# 胖身體：肩關節往外移到身體表面（動畫只有旋轉，平移不受影響）
SHOULDER_X = 0.185
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for bn, s in (("arm-left", 1), ("arm-right", -1)):
    eb = arm.data.edit_bones[bn]
    dx = s * SHOULDER_X - eb.head.x
    eb.head.x += dx; eb.tail.x += dx
bpy.ops.object.mode_set(mode="OBJECT")
arm.data.pose_position = 'REST'

# ---------- 材質 ----------
def hexc(h):
    h = h.lstrip('#')
    s = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in s] + [1.0]

MATS = {}
def mat(name, color, rough=0.85):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hexc(color)
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = hexc(color)
    MATS[name] = m
    return m

FUR = mat("fur", "#93653d")
CREAM = mat("cream", "#efd6a6")
DARK = mat("fur_dark", "#6e4a2c")
EAR_IN = mat("ear_inner", "#d9a27a")
VEST = mat("vest", "#66763a")
LEATHER = mat("leather", "#b5834c")
BUTTON = mat("button", "#9a6a38")
EYE = mat("eye", "#3b2414", 0.3)
PUPIL = mat("pupil", "#160c06", 0.2)
WHITE = mat("eye_white", "#fbf6ea", 0.3)
NOSE = mat("nose", "#3a2418", 0.35)
MOUTH = mat("mouth", "#b85a4c", 0.6)
TONGUE = mat("tongue", "#e58b7c", 0.6)
TEETH = mat("teeth", "#fffaf0", 0.4)
BLUSH = mat("blush", "#efa08a", 0.9)

PARTS = []  # (obj, bone)

def _finish(o, m, bone, smooth=True):
    o.data.materials.append(m)
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    PARTS.append((o, bone))
    return o

def ellipsoid(name, center, radii, m, bone, rot=(0, 0, 0), seg=32, ring=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=1.0, location=center, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = radii
    return _finish(o, m, bone)

def capsule(name, a, b, r, m, bone, scale_xy=(1, 1)):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0)
    o = bpy.context.object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    L = d.length
    for v in bm.verts:
        z = v.co.z
        v.co = Vector((v.co.x * r * scale_xy[0], v.co.y * r * scale_xy[1], z * r + (L if z > 0 else 0)))
    bm.to_mesh(o.data)
    bm.free()
    o.location = a
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return _finish(o, m, bone)

def rbox(name, center, size, m, bone, bevel=0.012, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    mod = o.modifiers.new("bev", 'BEVEL')
    mod.width = bevel
    mod.segments = 4
    return _finish(o, m, bone)

# ---------- 比例（參考圖：大頭、梨形身體、短手短腳） ----------
HEAD_C = Vector((0, 0, 0.50))
HEAD_R = Vector((0.215, 0.185, 0.18))

def head_surf(x, z, inset=0.0):
    """頭部橢球正面（-Y）在 (x,z) 的表面點"""
    dx, dz = x / HEAD_R.x, (z - HEAD_C.z) / HEAD_R.z
    t = max(0.0, 1 - dx * dx - dz * dz)
    return Vector((x, -HEAD_R.y * math.sqrt(t) + inset, z))

# 身體：梨形（下寬上窄）
body = ellipsoid("body", (0, 0.01, 0.215), (0.2, 0.17, 0.205), FUR, "torso")
bm = bmesh.new(); bm.from_mesh(body.data)
for v in bm.verts:  # 局部座標 z∈[-1,1]：下半部加寬
    k = 1.0 + 0.10 * max(0.0, -v.co.z) - 0.10 * max(0.0, v.co.z)
    v.co.x *= k; v.co.y *= k
bm.to_mesh(body.data); bm.free()
belly = ellipsoid("belly", (0, -0.08, 0.2), (0.125, 0.105, 0.16), CREAM, "torso")
tail = ellipsoid("tail", (0, 0.175, 0.07), (0.05, 0.035, 0.06), DARK, "torso", rot=(math.radians(-30), 0, 0))

# 頭
head = ellipsoid("head", HEAD_C, HEAD_R, FUR, "head")
cheek = ellipsoid("muzzle", (0, -0.115, 0.445), (0.145, 0.1, 0.092), CREAM, "head")
for s in (-1, 1):
    # 耳朵
    ellipsoid("ear", (s * 0.155, 0.01, 0.655), (0.052, 0.03, 0.05), FUR, "head", rot=(0, s * math.radians(-25), 0))
    ellipsoid("ear_in", (s * 0.155, -0.012, 0.65), (0.032, 0.012, 0.032), EAR_IN, "head", rot=(0, s * math.radians(-25), 0))
    # 腳掌
    ellipsoid("foot", (s * 0.088, -0.035, 0.028), (0.062, 0.078, 0.035), DARK, "leg-left" if s > 0 else "leg-right")
    capsule("leg", (s * 0.088, -0.005, 0.05), (s * 0.088, 0.0, 0.17), 0.055, FUR, "leg-left" if s > 0 else "leg-right")
    # 手臂（垂在身體兩側）
    # 手臂（靜止姿勢是 T 字，水平往外；動畫會把它轉下來）
    capsule("arm", (s * (SHOULDER_X - 0.01), 0.017, 0.288), (s * (SHOULDER_X + 0.09), 0.012, 0.284), 0.05, FUR, "arm-left" if s > 0 else "arm-right")
    ellipsoid("paw", (s * (SHOULDER_X + 0.105), 0.008, 0.283), (0.044, 0.044, 0.046), DARK, "arm-left" if s > 0 else "arm-right")

# 頭頂呆毛
for i, (dx, ang, h) in enumerate([(-0.022, -30, 0.05), (0.0, 0, 0.065), (0.022, 30, 0.05)]):
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.02, radius2=0.004, depth=h,
                                    location=(dx, 0.0, 0.672 + h * 0.4), rotation=(math.radians(-15), math.radians(ang), 0))
    o = bpy.context.object; o.name = "tuft"; _finish(o, FUR, "head")

# 鼻子、嘴巴、門牙
ellipsoid("nose", (0, -0.212, 0.482), (0.033, 0.021, 0.023), NOSE, "head")
ellipsoid("nose_hl", (-0.01, -0.23, 0.49), (0.008, 0.003, 0.005), WHITE, "head", seg=10, ring=5)

# ---------- 2D 臉：貼在頭和口鼻正面的薄殼，UV 從正面投影 ----------
# 臉貼圖範圍：x∈[-0.2,0.2]、z∈[0.32,0.72]（SVG 400x400，1px = 0.001），由 Godot 依表情換圖
FACE = mat("face", "#ffffff", 0.9)
FACE_X0, FACE_Z1, FACE_W = -0.2, 0.72, 0.4

def face_shell(name, center, radii, grow, keep):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0, location=center)
    o = bpy.context.object
    o.name = name
    o.scale = Vector(radii) + Vector((grow, grow, grow))
    bpy.ops.object.transform_apply(scale=True, location=True)
    bm = bmesh.new(); bm.from_mesh(o.data)
    kill = [f for f in bm.faces if not keep(f.calc_center_median(), f.normal)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")  # 球體原本就有 UVMap，要覆寫它
    for f in bm.faces:
        for l in f.loops:
            co = l.vert.co
            l[uv].uv = ((co.x - FACE_X0) / FACE_W, 1.0 - (FACE_Z1 - co.z) / FACE_W)
    xs = [v.co.x for v in bm.verts]; zs = [v.co.z for v in bm.verts]
    print("FACESHELL", name, round(min(xs), 3), round(max(xs), 3), round(min(zs), 3), round(max(zs), 3), "scale", tuple(o.scale))
    bm.to_mesh(o.data); bm.free()
    return _finish(o, FACE, "head")

face_shell("face_head", HEAD_C, HEAD_R, 0.0018,
           lambda c, n: n.y < -0.25 and 0.36 < c.z < 0.69 and abs(c.x) < 0.19)
face_shell("face_muzzle", Vector((0, -0.115, 0.445)), Vector((0.145, 0.1, 0.092)), 0.0018,
           lambda c, n: n.y < -0.15)

# ---------- 背心：身體上半部外殼，前面敞開 ----------
vest = ellipsoid("vest", (0, 0.01, 0.215), (0.2, 0.17, 0.205), VEST, "torso", seg=64, ring=32)
bm = bmesh.new(); bm.from_mesh(vest.data)
for v in bm.verts:
    k = 1.0 + 0.10 * max(0.0, -v.co.z) - 0.10 * max(0.0, v.co.z)
    v.co.x *= k * 1.06; v.co.y *= k * 1.07
def _vest_cut(c):
    phi = math.atan2(c.x, -c.y)  # 0 = 正前方
    return c.z < -0.3 or c.z > 0.84 or abs(phi) < 0.5 + 0.25 * max(0.0, c.z - 0.3)
kill = [f for f in bm.faces if _vest_cut(f.calc_center_median())]
bmesh.ops.delete(bm, geom=kill, context='FACES')
bm.to_mesh(vest.data); bm.free()
sol = vest.modifiers.new("thick", 'SOLIDIFY'); sol.thickness = 0.012; sol.offset = 1.0

# 身體外表面（背心/肚子）的投影，用來貼背帶和扣子
BODY_C, BODY_R = Vector((0, 0.01, 0.215)), Vector((0.2, 0.17, 0.205))
BELLY_C, BELLY_R = Vector((0, -0.08, 0.2)), Vector((0.125, 0.105, 0.16))
def _inside(p):
    l = Vector(((p.x - BODY_C.x) / BODY_R.x, (p.y - BODY_C.y) / BODY_R.y, (p.z - BODY_C.z) / BODY_R.z))
    k = 1.0 + 0.10 * max(0.0, -l.z) - 0.10 * max(0.0, l.z)
    if (l.x / (k * 1.06)) ** 2 + (l.y / (k * 1.07)) ** 2 + l.z ** 2 <= 1.0:
        return True
    b = Vector(((p.x - BELLY_C.x) / BELLY_R.x, (p.y - BELLY_C.y) / BELLY_R.y, (p.z - BELLY_C.z) / BELLY_R.z))
    return b.length_squared <= 1.0
def surface(c, d, margin):
    d = d.normalized(); t = 0.0; last = 0.0
    while t < 0.6:
        if _inside(c + d * t):
            last = t
        t += 0.002
    return c + d * (last + margin)

for i, z in enumerate((0.29, 0.2)):
    ang = -0.68
    d = Vector((math.sin(ang), -math.cos(ang), 0))
    p = surface(Vector((0, 0.01, z)), d, 0.012)
    ellipsoid("button", p, (0.015, 0.008, 0.015), BUTTON, "torso", seg=12, ring=6, rot=(0, 0, ang))

# ---------- 斜背包：背帶從右肩斜到左腰，貼著身體表面 ----------
th = math.radians(44)
U, V = Vector((math.cos(th), 0, -math.sin(th))), Vector((0, 1, 0))
SC = Vector((0, 0.01, 0.285))
pts = [surface(SC, U * math.cos(2 * math.pi * i / 96) + V * math.sin(2 * math.pi * i / 96), 0.01) for i in range(96)]
cu = bpy.data.curves.new("strap", 'CURVE'); cu.dimensions = '3D'
cu.bevel_depth = 0.011; cu.bevel_resolution = 2
sp = cu.splines.new('POLY'); sp.points.add(len(pts) - 1); sp.use_cyclic_u = True
for i, p in enumerate(pts):
    sp.points[i].co = (p.x, p.y, p.z, 1)
so = bpy.data.objects.new("strap", cu); bpy.context.scene.collection.objects.link(so)
bpy.context.view_layer.objects.active = so; so.select_set(True)
bpy.ops.object.convert(target='MESH'); so.select_set(False)
so.scale = (1, 1, 1)
_finish(so, LEATHER, "torso")
bp = surface(Vector((0, 0.0, 0.13)), Vector((0.75, -0.66, 0)), 0.03)
rbox("bag", bp, (0.1, 0.05, 0.085), LEATHER, "torso", bevel=0.018, rot=(0, 0, math.radians(38)))
rbox("bag_flap", bp + Vector((0.016, -0.02, 0.022)), (0.092, 0.014, 0.048), LEATHER, "torso", bevel=0.01, rot=(math.radians(6), 0, math.radians(38)))
ellipsoid("bag_btn", bp + Vector((0.02, -0.03, 0.004)), (0.011, 0.006, 0.011), BUTTON, "torso", seg=12, ring=6, rot=(0, 0, math.radians(38)))

# ---------- 合併、綁骨 ----------
bpy.ops.object.select_all(action='DESELECT')
for o, bone in PARTS:
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for md in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.select_set(False)
    vg = o.vertex_groups.new(name=bone)
    vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
for o, _ in PARTS:
    o.select_set(True)
bpy.context.view_layer.objects.active = PARTS[0][0]
bpy.ops.object.join()
mesh = bpy.context.object
mesh.name = "gopher-mesh"
mesh.parent = arm
md = mesh.modifiers.new("Armature", 'ARMATURE')
md.object = arm
arm.data.pose_position = 'POSE'

print("PARTS", len(PARTS), "verts", len(mesh.data.vertices), "dims", tuple(round(v, 3) for v in mesh.dimensions))

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True,
                          export_animation_mode='ACTIONS', export_apply=False, export_yup=True)
print("EXPORTED", OUT)

# ---------- 預覽圖 ----------
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
    sc.display.shading.show_object_outline = False
    sc.render.resolution_x = 700; sc.render.resolution_y = 800
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("w"); sc.world = world
    world.color = (0.95, 0.93, 0.88)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.85
    target = Vector((0, 0, 0.36))
    for nm, yaw in (("front", 0), ("three_quarter", 35), ("side", 90), ("back", 180)):
        a = math.radians(yaw)
        cam.location = target + Vector((math.sin(a) * -2.0 * -1, -math.cos(a) * 2.0, 0.25))
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(PREVIEW, f"gopher_{nm}.png")
        bpy.ops.render.render(write_still=True)
    print("PREVIEWS", PREVIEW)
