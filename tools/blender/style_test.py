# 繪本風格測試圖（不進遊戲）：metaball 一體成形的土撥鼠＋程式生成的筆刷毛材質＋短毛＋暖色逆光＋景深。
# 用法：blender -b --factory-startup --python tools/blender/style_test.py -- <out.png> [samples]
import bpy, bmesh, sys, math, random
from mathutils import Vector, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
SAMPLES = int(args[1]) if len(args) > 1 else 64
random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def srgb(h):
    h = h.lstrip('#')
    s = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in s] + [1.0]

# ---------------- 節點小工具 ----------------
class NB:
    def __init__(self, mat):
        mat.use_nodes = True
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.tc = self.nt.nodes.new("ShaderNodeTexCoord")

    def n(self, t, **props):
        node = self.nt.nodes.new(t)
        for k, v in props.items():
            setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)

    def _in(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.link(v, sock)
        else:
            sock.default_value = v

    def math(self, op, a, b=0.0, clamp=False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._in(m.inputs[0], a); self._in(m.inputs[1], b)
        return m.outputs[0]

    def vmath(self, op, a, b=None):
        m = self.n("ShaderNodeVectorMath", operation=op)
        self._in(m.inputs[0], a)
        if b is not None:
            self._in(m.inputs[1], b)
        return m.outputs[1] if op in ("LENGTH", "DOT_PRODUCT", "DISTANCE") else m.outputs[0]

    def smooth(self, v, a, b, to_a=0.0, to_b=1.0):
        m = self.n("ShaderNodeMapRange", interpolation_type='SMOOTHSTEP', clamp=True)
        self._in(m.inputs[0], v)
        m.inputs[1].default_value = a; m.inputs[2].default_value = b
        m.inputs[3].default_value = to_a; m.inputs[4].default_value = to_b
        return m.outputs[0]

    def mix(self, fac, a, b):
        m = self.n("ShaderNodeMix", data_type='RGBA')
        self._in(m.inputs[0], fac); self._in(m.inputs[6], a); self._in(m.inputs[7], b)
        return m.outputs[2]

    def noise(self, vec, scale, detail=3.0, rough=0.5, distortion=0.0):
        t = self.n("ShaderNodeTexNoise")
        self._in(t.inputs["Vector"], vec)
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["Distortion"].default_value = distortion
        return t.outputs["Fac"]

    def stretch(self, vec, sx, sy, sz):
        m = self.n("ShaderNodeMapping")
        self._in(m.inputs["Vector"], vec)
        m.inputs["Scale"].default_value = (sx, sy, sz)
        return m.outputs[0]

    def principled(self, color, rough=0.8, sheen=0.0, sss=0.0, coat=0.0, bump=None, emission=None, estr=0.0):
        p = self.n("ShaderNodeBsdfPrincipled")
        self._in(p.inputs["Base Color"], color)
        p.inputs["Roughness"].default_value = rough
        try:
            p.inputs["Sheen Weight"].default_value = sheen
            p.inputs["Sheen Roughness"].default_value = 0.6
            p.inputs["Subsurface Weight"].default_value = sss
            p.inputs["Subsurface Radius"].default_value = (0.01, 0.006, 0.004)
            p.inputs["Coat Weight"].default_value = coat
            p.inputs["Specular IOR Level"].default_value = 0.35
        except KeyError as e:
            print("WARN principled", e)
        if bump is not None:
            b = self.n("ShaderNodeBump")
            b.inputs["Strength"].default_value = 0.35
            b.inputs["Distance"].default_value = 0.003
            self._in(b.inputs["Height"], bump)
            self.link(b.outputs[0], p.inputs["Normal"])
        if emission is not None:
            self._in(p.inputs["Emission Color"], emission)
            p.inputs["Emission Strength"].default_value = estr
        self.link(p.outputs[0], self.out.inputs[0])
        return p

    def ell_mask(self, pos, c, r, edge_noise, soft=0.2):
        d = self.vmath('DIVIDE', self.vmath('SUBTRACT', pos, Vector(c)), Vector(r))
        L = self.math('ADD', self.vmath('LENGTH', d), self.math('MULTIPLY', self.math('SUBTRACT', edge_noise, 0.5), 0.35))
        return self.smooth(L, 1.0 - soft, 1.0, 1.0, 0.0)


def mat_simple(name, color, rough=0.6, coat=0.0, emission=None, estr=0.0, sheen=0.0, grain=0.0):
    m = bpy.data.materials.new(name)
    nb = NB(m)
    pos = nb.tc.outputs["Object"]
    col = srgb(color)
    bump = None
    if grain > 0:
        g = nb.noise(pos, grain, 4.0, 0.6)
        hs = nb.n("ShaderNodeHueSaturation")
        nb._in(hs.inputs["Color"], col)
        nb._in(hs.inputs["Value"], nb.math('ADD', nb.math('MULTIPLY', g, 0.3), 0.85))
        col = hs.outputs[0]
        bump = g
    nb.principled(col, rough, sheen=sheen, coat=coat, bump=bump, emission=srgb(emission) if emission else None, estr=estr)
    return m

# ---------------- 毛的材質：漸層色塊＋筆刷紋理 ----------------
FUR_C, CREAM_C, DARK_C, BLUSH_C = "#9b6a3c", "#f1d7a6", "#6b4325", "#e98f7a"
MUZZLE = ((0, -0.15, 0.435), (0.15, 0.12, 0.105))
BELLY = ((0, -0.13, 0.2), (0.14, 0.12, 0.17))
CHEEKS = [((s * 0.125, -0.15, 0.455), (0.04, 0.05, 0.03)) for s in (-1, 1)]
PAWS = [((s * 0.215, -0.03, 0.16), (0.055, 0.06, 0.05)) for s in (-1, 1)]

def fur_material():
    m = bpy.data.materials.new("fur")
    nb = NB(m)
    pos = nb.tc.outputs["Object"]
    edge = nb.noise(pos, 18.0, 3.0, 0.6)
    cream = nb.math('MAXIMUM', nb.ell_mask(pos, *MUZZLE, edge, 0.28), nb.ell_mask(pos, *BELLY, edge, 0.25))
    sep = nb.n("ShaderNodeSeparateXYZ"); nb.link(pos, sep.inputs[0])
    feet = nb.smooth(sep.outputs[2], 0.075, 0.045)
    paws = nb.math('MAXIMUM', nb.ell_mask(pos, *PAWS[0], edge, 0.3), nb.ell_mask(pos, *PAWS[1], edge, 0.3))
    dark = nb.math('MAXIMUM', feet, paws)
    blush = nb.math('MAXIMUM', nb.ell_mask(pos, *CHEEKS[0], edge, 0.6), nb.ell_mask(pos, *CHEEKS[1], edge, 0.6))
    # 背面與頭頂稍深
    back = nb.smooth(sep.outputs[1], -0.02, 0.16)
    col = nb.mix(cream, srgb(FUR_C), srgb(CREAM_C))
    col = nb.mix(nb.math('MULTIPLY', back, 0.35), col, srgb("#7d5330"))
    col = nb.mix(dark, col, srgb(DARK_C))
    col = nb.mix(nb.math('MULTIPLY', blush, 0.55), col, srgb(BLUSH_C))
    # 筆刷：沿身體往下的短筆觸（z 方向拉長的噪點）＋細顆粒
    strokes = nb.noise(nb.stretch(pos, 70, 70, 22), 1.0, 6.0, 0.65, 0.4)
    grain = nb.noise(pos, 260.0, 2.0, 0.5)
    tex = nb.math('ADD', nb.math('MULTIPLY', strokes, 0.75), nb.math('MULTIPLY', grain, 0.25))
    hi = nb.n("ShaderNodeHairInfo")
    strand_dark = nb.math('SUBTRACT', 1.0, nb.math('MULTIPLY', hi.outputs["Is Strand"], 0.22))
    hs = nb.n("ShaderNodeHueSaturation")
    nb._in(hs.inputs["Color"], col)
    nb._in(hs.inputs["Saturation"], nb.math('ADD', 1.0, nb.math('MULTIPLY', hi.outputs["Is Strand"], 0.15)))
    nb._in(hs.inputs["Value"], nb.math('MULTIPLY', nb.math('ADD', nb.math('MULTIPLY', tex, 0.42), 0.8), strand_dark))
    nb.principled(hs.outputs[0], 0.85, sheen=0.5, sss=0.12, bump=tex)
    return m

FUR = fur_material()
VEST = mat_simple("vest", "#6f8b3a", 0.9, sheen=0.7, grain=380)
LEATHER = mat_simple("leather", "#9a6634", 0.55, grain=120)
WOOD = mat_simple("button", "#7a5230", 0.5, grain=90)
NOSE = mat_simple("nose", "#2e1a10", 0.25, coat=0.8)
MOUTH = mat_simple("mouth", "#7e2c22", 0.6)
TONGUE = mat_simple("tongue", "#e47e72", 0.45, coat=0.3)
TEETH = mat_simple("teeth", "#fff6e6", 0.35)
EARIN = mat_simple("ear_inner", "#c98c68", 0.8, sheen=0.5, grain=200)
HL = mat_simple("highlight", "#ffffff", 0.2, emission="#ffffff", estr=3.0)
LINE = mat_simple("line", "#3a2214", 0.6)

def eye_material():
    m = bpy.data.materials.new("eye")
    nb = NB(m)
    pos = nb.tc.outputs["Object"]  # 眼球物件局部座標，半徑 1
    sep = nb.n("ShaderNodeSeparateXYZ"); nb.link(pos, sep.inputs[0])
    # 正面看（x,z）距離中心；中心略往上，讓下緣比較亮
    dx = sep.outputs[0]
    dz = nb.math('SUBTRACT', sep.outputs[2], 0.12)
    r = nb.math('SQRT', nb.math('ADD', nb.math('MULTIPLY', dx, dx), nb.math('MULTIPLY', dz, dz)))
    ramp = nb.n("ShaderNodeValToRGB")
    nb.link(r, ramp.inputs[0])
    els = ramp.color_ramp.elements
    els[0].position = 0.0; els[0].color = srgb("#0d0603")
    els[1].position = 1.0; els[1].color = srgb("#24120a")
    for p, c in ((0.42, "#140904"), (0.5, "#4b2812"), (0.78, "#9a6430"), (0.92, "#3a1e0e")):
        e = els.new(p); e.color = srgb(c)
    nb.principled(ramp.outputs[0], 0.06, coat=1.0)
    return m

EYE = eye_material()

# ---------------- Metaball 身體（頭、臉頰、口鼻、身體、手、腳會自然融合） ----------------
mb = bpy.data.metaballs.new("body")
mb.resolution = 0.006
mb.render_resolution = 0.004
mb.threshold = 0.6
mbo = bpy.data.objects.new("gopher", mb)
scene.collection.objects.link(mbo)

def ball(co, size, kind='ELLIPSOID', rot=None, stiff=2.0):
    e = mb.elements.new(type=kind)
    e.co = co
    e.radius = 1.0
    e.stiffness = stiff
    if kind == 'ELLIPSOID':
        e.size_x, e.size_y, e.size_z = size
    else:
        e.size_x = size[0]
        e.radius = size[1]
    if rot is not None:
        e.rotation = rot
    return e

K = 1.0 / 0.62  # metaball 可見表面約是 size 的 0.62，先放大
ball((0, 0, 0.5), Vector((0.222, 0.188, 0.182)) * K)               # 頭
for s in (-1, 1):
    ball((s * 0.11, -0.06, 0.43), Vector((0.112, 0.1, 0.088)) * K, stiff=1.6)  # 臉頰肉
ball((0, -0.115, 0.45), Vector((0.085, 0.08, 0.07)) * K, stiff=1.6)        # 口鼻
ball((0, 0.01, 0.2), Vector((0.198, 0.17, 0.185)) * K)              # 身體
ball((0, -0.05, 0.13), Vector((0.17, 0.14, 0.1)) * K, stiff=1.5)       # 下腹（梨形）
for s in (-1, 1):
    a, b = Vector((s * 0.18, -0.01, 0.3)), Vector((s * 0.215, -0.035, 0.17))
    d = (b - a)
    q = Vector((1, 0, 0)).rotation_difference(d.normalized())
    ball((a + b) / 2, (d.length / 2, 0.045 * K * 0.85), kind='CAPSULE', rot=q, stiff=2.0)  # 手臂
    ball((s * 0.088, -0.05, 0.03), Vector((0.058, 0.075, 0.035)) * K, stiff=2.0)  # 腳

bpy.context.view_layer.objects.active = mbo
mbo.select_set(True)
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(mbo.evaluated_get(dg))
body = bpy.data.objects.new("gopher_mesh", me)
scene.collection.objects.link(body)
bpy.data.objects.remove(mbo, do_unlink=True)
body.data.materials.append(FUR)
for p in body.data.polygons:
    p.use_smooth = True
print("BODY dims", tuple(round(v, 3) for v in body.dimensions), "verts", len(me.vertices))

# 射線找表面（從外往內）
def surf(origin, direction, objs=None):
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, nor, idx, ob, mat = scene.ray_cast(dg, Vector(origin), Vector(direction).normalized())
    return (loc, nor) if hit else (None, None)

def front(x, z):
    return surf((x, -1.0, z), (0, 1, 0))

def add_ell(name, loc, radii, m, rot=None, seg=32, ring=16, quat=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=ring, radius=1.0, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = radii
    if quat is not None:
        o.rotation_mode = 'QUATERNION'; o.rotation_quaternion = quat
    elif rot is not None:
        o.rotation_euler = rot
    o.data.materials.append(m)
    for p in o.data.polygons:
        p.use_smooth = True
    return o

def facing(nor):
    # 讓物件的 -Y 對齊表面法線
    return Vector((0, -1, 0)).rotation_difference(nor)

def capsule_line(name, pts, r, m):
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'
    cu.bevel_depth = r; cu.bevel_resolution = 3; cu.use_fill_caps = True
    sp = cu.splines.new('POLY'); sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        sp.points[i].co = (p.x, p.y, p.z, 1)
    o = bpy.data.objects.new(name, cu); scene.collection.objects.link(o)
    o.data.materials.append(m)
    return o

# ---------------- 臉 ----------------
for s in (-1, 1):
    loc, nor = front(s * 0.077, 0.528)
    q = facing(nor)
    # 眼窩的深色細邊
    add_ell("eye_line", loc - nor * 0.006, (0.039, 0.012, 0.043), LINE, quat=q)
    eye = add_ell("eye", loc - nor * 0.003, (0.035, 0.011, 0.039), EYE, quat=q)
    hl = add_ell("hl", loc + nor * 0.008 + q @ Vector((s * 0.0 + 0.011, 0, 0.014)), (0.0095, 0.003, 0.0095), HL, quat=q, seg=16, ring=8)
    add_ell("hl2", loc + nor * 0.008 + q @ Vector((-0.012, 0, -0.014)), (0.0048, 0.002, 0.0048), HL, quat=q, seg=12, ring=6)
    # 眉毛：短短的深色筆觸
    b1, _ = front(s * 0.06, 0.598); b2, _ = front(s * 0.094, 0.592)
    if b1 and b2:
        capsule_line("brow", [b1 + Vector((0, -0.002, 0)), b2 + Vector((0, -0.002, 0))], 0.0055, LINE)
    # 耳朵
    eloc, enor = surf((s * 0.33, 0.0, 0.75), (-s * 0.6, 0, -1.0))
    if eloc:
        add_ell("ear", eloc + Vector((s * 0.01, 0.01, 0.012)), (0.06, 0.034, 0.056), FUR, rot=(0, s * math.radians(-28), 0))
        add_ell("ear_in", eloc + Vector((s * 0.01, -0.012, 0.01)), (0.037, 0.014, 0.036), EARIN, rot=(0, s * math.radians(-28), 0))

# 鼻子
nloc, nnor = front(0, 0.478)
add_ell("nose", nloc + Vector((0, 0.004, 0)), (0.031, 0.02, 0.022), NOSE)
add_ell("nose_hl", nloc + Vector((-0.009, -0.016, 0.009)), (0.008, 0.003, 0.005), HL, seg=12, ring=6)
# 嘴：張開的小嘴（凹進去的深紅）＋舌頭＋兩顆門牙＋ω 嘴線
mloc, mnor = front(0, 0.432)
add_ell("mouth", mloc + Vector((0, 0.006, 0)), (0.028, 0.012, 0.026), MOUTH)
add_ell("tongue", mloc + Vector((0, -0.002, -0.012)), (0.018, 0.008, 0.011), TONGUE)
for s in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=mloc + Vector((s * 0.0085, -0.0025, 0.011)))
    t = bpy.context.object; t.name = "tooth"; t.scale = (0.014, 0.006, 0.019)
    bpy.ops.object.transform_apply(scale=True)
    bv = t.modifiers.new("b", 'BEVEL'); bv.width = 0.003; bv.segments = 3
    t.data.materials.append(TEETH)
pts = []
for i in range(17):
    u = -1 + i / 8
    x = u * 0.045
    z = 0.452 - 0.012 * math.sin(abs(u) * math.pi) + 0.006 * abs(u)
    p, _ = front(x, z)
    if p:
        pts.append(p + Vector((0, -0.0015, 0)))
capsule_line("smile", pts, 0.0035, LINE)
p1, _ = front(0, 0.458); p2, _ = front(0, 0.447)
capsule_line("philtrum", [p1 + Vector((0, -0.002, 0)), p2 + Vector((0, -0.002, 0))], 0.0035, LINE)

# ---------------- 背心：沿著身體表面複製一層，前面敞開 ----------------
vest = body.copy(); vest.data = body.data.copy(); vest.name = "vest"
scene.collection.objects.link(vest)
vest.data.materials.clear(); vest.data.materials.append(VEST)
bm = bmesh.new(); bm.from_mesh(vest.data)
def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length
ARMS = [(Vector((s * 0.18, -0.01, 0.3)), Vector((s * 0.215, -0.035, 0.17))) for s in (-1, 1)]
def _vest_keep(c):
    if any(_seg_dist(c, a, b) < 0.064 for a, b in ARMS):
        return False
    phi = math.atan2(c.x, -c.y)
    if c.z < 0.15 or c.z > 0.36:
        return False
    return abs(phi) > 0.42 + 0.3 * max(0.0, (c.z - 0.3) / 0.06)
kill = [f for f in bm.faces if not _vest_keep(f.calc_center_median())]
bmesh.ops.delete(bm, geom=kill, context='FACES')
bm.to_mesh(vest.data); bm.free()
so = vest.modifiers.new("thick", 'SOLIDIFY'); so.thickness = 0.011; so.offset = 1.0
vest.modifiers.new("sm", 'SUBSURF').levels = 1
# 扣子
for z in (0.3, 0.215):
    loc, nor = surf((-0.55, -0.9, z), (0.55, 0.9, 0))
    if loc:
        add_ell("button", loc + nor * 0.004, (0.013, 0.006, 0.013), WOOD, quat=facing(nor), seg=16, ring=8)

# ---------------- 斜背包 ----------------
th = math.radians(42)
U, V = Vector((math.cos(th), 0, -math.sin(th))), Vector((0, 1, 0))
C = Vector((0, 0.01, 0.285))
spts = []
for i in range(96):
    a = 2 * math.pi * i / 96
    d = U * math.cos(a) + V * math.sin(a)
    loc, nor = surf(C + d * 0.6, -d)
    if loc:
        spts.append(loc + nor * 0.008)
strap = capsule_line("strap", spts + spts[:1], 0.009, LEATHER)
strap.data.bevel_mode = 'ROUND'
bloc, bnor = surf((0.7, -0.62, 0.13), (-0.7, 0.62, 0))
bpy.ops.mesh.primitive_cube_add(size=1.0, location=bloc + bnor * 0.03)
bag = bpy.context.object; bag.name = "bag"; bag.scale = (0.1, 0.05, 0.085)
bag.rotation_mode = 'QUATERNION'; bag.rotation_quaternion = facing(bnor)
bpy.ops.object.transform_apply(scale=True)
bv = bag.modifiers.new("b", 'BEVEL'); bv.width = 0.018; bv.segments = 5
bag.data.materials.append(LEATHER)
add_ell("bag_btn", bloc + bnor * 0.058 + Vector((0, 0, 0.008)), (0.01, 0.005, 0.01), WOOD, quat=facing(bnor), seg=12, ring=6)

# ---------------- 短毛（毛茸茸的輪廓） ----------------
vg = body.vertex_groups.new(name="hair")
feats = [Vector((s * 0.077, -0.17, 0.528)) for s in (-1, 1)] + [Vector((0, -0.22, 0.47)), Vector((0, -0.2, 0.435))]
for v in body.data.vertices:
    p = v.co
    w = 1.0
    for f in feats:
        d = (p - f).length
        w = min(w, max(0.0, (d - 0.05) / 0.04))
    # 背心底下不用長毛
    if 0.16 < p.z < 0.35 and abs(math.atan2(p.x, -p.y)) > 0.6 and min(_seg_dist(p, a, b) for a, b in ARMS) > 0.07:
        w = min(w, 0.15)
    vg.add([v.index], w, 'REPLACE')
pm = body.modifiers.new("fur", 'PARTICLE_SYSTEM')
ps = body.particle_systems[0]
st = ps.settings
st.type = 'HAIR'
st.count = 7000
st.hair_length = 0.0048
st.factor_random = 0.0025
st.use_advanced_hair = True
st.child_type = 'INTERPOLATED'
st.rendered_child_count = 4
st.child_percent = 20
st.clump_factor = 0.55
st.roughness_1 = 0.0015
st.roughness_endpoint = 0.001
st.root_radius = 1.0
st.tip_radius = 0.1
st.radius_scale = 0.0017
st.material = 1
ps.vertex_group_density = "hair"
ps.vertex_group_length = "hair"

# ---------------- 場景：苔石地面、背景、螢火蟲 ----------------
def plane_bg():
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0.6, 3.2, 1.2), rotation=(math.radians(90), 0, 0))
    o = bpy.context.object; o.scale = (9, 5, 1)
    m = bpy.data.materials.new("backdrop")
    nb = NB(m)
    pos = nb.tc.outputs["Object"]
    sep = nb.n("ShaderNodeSeparateXYZ"); nb.link(pos, sep.inputs[0])
    blot = nb.noise(pos, 4.0, 4.0, 0.6, 0.8)
    warm = nb.smooth(nb.math('ADD', sep.outputs[0], nb.math('MULTIPLY', blot, 0.5)), 0.1, -0.35)
    col = nb.mix(warm, srgb("#0f2622"), srgb("#b77a2c"))
    col = nb.mix(nb.math('MULTIPLY', nb.smooth(blot, 0.45, 0.7), 0.6), col, srgb("#2f4a24"))
    em = nb.n("ShaderNodeEmission"); nb._in(em.inputs[0], col); em.inputs[1].default_value = 0.9
    nb.link(em.outputs[0], nb.out.inputs[0])
    o.data.materials.append(m)
plane_bg()

bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=0.9, depth=0.3, location=(0, 0.1, -0.15))
ground = bpy.context.object
gm = bpy.data.materials.new("moss")
nb = NB(gm)
pos = nb.tc.outputs["Object"]
n1 = nb.noise(pos, 6.0, 5.0, 0.6, 0.6)
n2 = nb.noise(pos, 90.0, 3.0, 0.6)
col = nb.mix(nb.smooth(n1, 0.4, 0.6), srgb("#3a3024"), srgb("#34481f"))
hs = nb.n("ShaderNodeHueSaturation"); nb._in(hs.inputs["Color"], col)
nb._in(hs.inputs["Value"], nb.math('ADD', nb.math('MULTIPLY', n2, 0.4), 0.8))
nb.principled(hs.outputs[0], 0.95, sheen=0.0, bump=n2)
ground.data.materials.append(gm)
bv = ground.modifiers.new("b", 'BEVEL'); bv.width = 0.08; bv.segments = 6
for (x, y, s) in ((-0.55, 0.45, 0.22), (0.62, 0.55, 0.28), (-0.75, -0.2, 0.12)):
    r = add_ell("rock", (x, y, 0.0), (s, s * 0.8, s * 0.6), gm)
# 前景葉子（失焦）
leaf = mat_simple("leaf", "#4f7a2e", 0.6, sheen=0.3, grain=40)
for (x, y, z, rz) in ((-0.62, -0.75, 0.1, 30), (0.75, -0.6, 0.06, -40)):
    add_ell("leaf", (x, y, z), (0.16, 0.012, 0.07), leaf, rot=(math.radians(20), math.radians(rz), math.radians(rz)))
# 螢火蟲
glow = mat_simple("firefly", "#ffd36b", 0.5, emission="#ffcf5a", estr=40.0)
for i in range(26):
    p = (random.uniform(-1.4, 1.6), random.uniform(-0.5, 2.6), random.uniform(0.05, 1.5))
    if abs(p[0]) < 0.35 and p[1] < 0.4:
        continue
    add_ell("ff", p, (0.008,) * 3, glow, seg=10, ring=5)

# ---------------- 燈光 ----------------
def light(name, kind, loc, energy, color, size=0.5, target=(0, 0, 0.4)):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = srgb(color)[:3]
    if kind == 'AREA':
        ld.size = size
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    scene.collection.objects.link(o)
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o

light("key", 'AREA', (-1.0, -1.3, 1.5), 42, "#ffe2b8", 1.2)
light("rim", 'AREA', (0.9, 1.1, 1.2), 90, "#ffb35a", 0.6)
light("rim2", 'AREA', (-0.9, 0.9, 0.9), 35, "#ffcf7a", 0.5)
light("fill", 'AREA', (1.4, -0.8, 0.5), 10, "#7fb7c0", 1.5)
light("bounce", 'POINT', (0.1, -0.45, 0.05), 2.0, "#ffc060")

world = bpy.data.worlds.new("w"); scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = srgb("#1c2e2a")
bg.inputs[1].default_value = 0.6

# ---------------- 相機、渲染 ----------------
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam); scene.camera = cam
cam.location = (0.5, -2.05, 0.62)
target = Vector((0.03, 0, 0.36))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 62
cam.data.dof.use_dof = True
cam.data.dof.focus_distance = (Vector((0, -0.18, 0.5)) - cam.location).length
cam.data.dof.aperture_fstop = 2.2

for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
try:
    scene.eevee.taa_render_samples = SAMPLES
    scene.eevee.use_raytracing = True
    scene.eevee.use_shadows = True
except Exception as e:
    print("WARN eevee", e)
scene.render.hair_type = 'STRIP'
scene.render.resolution_x = 1280
scene.render.resolution_y = 960
try:
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
except Exception as e:
    print("WARN look", e)

# 光暈（Bloom）
try:
    ng = bpy.data.node_groups.new("comp", "CompositorNodeTree")
    scene.compositing_node_group = ng
    rl = ng.nodes.new("CompositorNodeRLayers")
    gl = ng.nodes.new("CompositorNodeGlare")
    try:
        gl.glare_type = 'BLOOM'
    except Exception:
        try:
            gl.inputs["Type"].default_value = 'Bloom'
        except Exception as e:
            print("WARN glare type", e)
    for k, v in (("Strength", 0.55), ("Size", 0.7), ("Threshold", 0.85)):
        if k in gl.inputs:
            gl.inputs[k].default_value = v
    ng.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    go = ng.nodes.new("NodeGroupOutput")
    ng.links.new(rl.outputs["Image"], gl.inputs["Image"])
    ng.links.new(gl.outputs[0], go.inputs[0])
    print("BLOOM ok")
except Exception as e:
    print("WARN bloom", e)

scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
bpy.ops.wm.save_as_mainfile(filepath=OUT.replace(".png", ".blend"))
