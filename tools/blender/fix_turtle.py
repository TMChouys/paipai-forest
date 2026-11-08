# 慢慢館長（混元 3D 生成的烏龜）修正：
#   1. 皮膚改成帶綠的烏龜膚色（依 3D 位置重畫：頭頂的接縫、太多的老人斑一起消掉，只留幾顆淡淡的斑）
#   2. 背後換成很大很重的龜殼（程式產生的圓頂＋手繪感的六角甲片貼圖）
#   3. 破破的披風：外面重新包一層完整的披風（紫色、金邊、厚度），原本的披風貼圖也改成紫色
# 用法：blender -b --factory-startup --python tools/blender/fix_turtle.py -- <in.glb> <out.glb> [預覽資料夾]
# 座標：Blender Z 向上、角色面向 -Y，和原檔同尺度（高約 1.97），之後再交給 rig_hy3d.py（turtle）上骨架。
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREVIEW = args[2] if len(args) > 2 else None

# ---- 顏色（sRGB 0..1）----
SKIN = np.array([0.60, 0.70, 0.44])        # 帶綠的烏龜膚色
SKIN_SPOT = np.array([0.48, 0.57, 0.33])   # 淡淡的老人斑
PURPLE_H = 0.76                             # 披風紫色的色相
CLOAK = np.array([0.40, 0.26, 0.57])
CLOAK_DARK = np.array([0.27, 0.17, 0.40])
GOLD = np.array([0.86, 0.69, 0.33])
SHELL = np.array([0.64, 0.45, 0.27])
SHELL_LIGHT = np.array([0.76, 0.56, 0.34])
SHELL_GROOVE = np.array([0.36, 0.23, 0.13])
SHELL_RIM = np.array([0.55, 0.38, 0.22])

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)

def rgb_to_hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx = c.max(-1); mn = c.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r); gm = m & (mx == g) & ~rm; bm_ = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm_] = (r - g)[bm_] / d[bm_] + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx

def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel] = np.stack([a[sel], b[sel], c[sel]], -1)
    return out

def noise3(P, f=6.0, seed=0.0):
    # 低頻的水彩感起伏（幾個正弦相加，-1..1）
    x, y, z = P[..., 0] * f, P[..., 1] * f, P[..., 2] * f
    n = (np.sin(x * 1.3 + y * 0.7 + seed) + np.sin(y * 1.7 - z * 1.1 + 2.0 + seed)
         + np.sin(z * 1.5 + x * 0.9 + 4.0 + seed) + 0.5 * np.sin((x + y + z) * 2.9 + seed))
    return n / 3.5

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC, merge_vertices=True, import_shading="SMOOTH")
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.data.objects):
    if o != body:
        bpy.data.objects.remove(o, do_unlink=True)
body.name = "turtle-body"

bm0 = bmesh.new(); bm0.from_mesh(body.data)
bvh = BVHTree.FromBMesh(bm0)

# ================= 1. 貼圖：每個貼圖像素的 3D 位置與法線 =================
img = next(n.image for m in body.data.materials if m and m.use_nodes
           for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image)
W, Hh = img.size
pix = np.array(img.pixels[:], dtype=np.float32).reshape(Hh, W, 4)
pos = np.zeros((Hh, W, 3), np.float32)
nor = np.zeros((Hh, W, 3), np.float32)
have = np.zeros((Hh, W), bool)
uvl = body.data.uv_layers.active.data
vco = np.array([v.co[:] for v in body.data.vertices])
vno = np.array([v.normal[:] for v in body.data.vertices])
yy, xx = np.mgrid[0:Hh, 0:W]
for poly in body.data.polygons:
    vi = list(poly.vertices)
    uv = np.array([uvl[li].uv[:] for li in poly.loop_indices]) * [W, Hh]
    for k in range(1, len(vi) - 1):
        tri = uv[[0, k, k + 1]]; P3 = vco[[vi[0], vi[k], vi[k + 1]]]; N3 = vno[[vi[0], vi[k], vi[k + 1]]]
        x0, y0 = np.floor(tri.min(0)).astype(int) - 1
        x1, y1 = np.ceil(tri.max(0)).astype(int) + 1
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, W - 1), min(y1, Hh - 1)
        if x1 < x0 or y1 < y0:
            continue
        X = xx[y0:y1 + 1, x0:x1 + 1] + 0.5; Y = yy[y0:y1 + 1, x0:x1 + 1] + 0.5
        (ax, ay), (bx, by), (cx2, cy2) = tri
        den = (by - cy2) * (ax - cx2) + (cx2 - bx) * (ay - cy2)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy2) * (X - cx2) + (cx2 - bx) * (Y - cy2)) / den
        l2 = ((cy2 - ay) * (X - cx2) + (ax - cx2) * (Y - cy2)) / den
        l3 = 1 - l1 - l2
        inside = (l1 >= -0.08) & (l2 >= -0.08) & (l3 >= -0.08)
        Q = l1[..., None] * P3[0] + l2[..., None] * P3[1] + l3[..., None] * P3[2]
        Nn = l1[..., None] * N3[0] + l2[..., None] * N3[1] + l3[..., None] * N3[2]
        sub = pos[y0:y1 + 1, x0:x1 + 1]; nsub = nor[y0:y1 + 1, x0:x1 + 1]; hs = have[y0:y1 + 1, x0:x1 + 1]
        sub[inside] = Q[inside]; nsub[inside] = Nn[inside]; hs[inside] = True
# UV 島邊緣的填充像素：往外擴幾格，拿最近的位置
for _ in range(4):
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        src = np.roll(np.roll(have, dy, 0), dx, 1)
        fill = src & ~have
        if fill.any():
            pos[fill] = np.roll(np.roll(pos, dy, 0), dx, 1)[fill]
            nor[fill] = np.roll(np.roll(nor, dy, 0), dx, 1)[fill]
            have |= fill
nor /= np.maximum(np.linalg.norm(nor, axis=-1, keepdims=True), 1e-6)
print("RASTER texels", int(have.sum()))

rgb = pix[..., :3].astype(np.float64)
h, s, v = rgb_to_hsv(rgb)
X, Y, Z = pos[..., 0], pos[..., 1], pos[..., 2]

# ---- 披風：藍綠／灰藍色 → 紫色（保留明暗和彩度的變化）----
teal = smoothstep(0.19, 0.24, h) * (1 - smoothstep(0.66, 0.72, h)) * smoothstep(0.025, 0.06, s) * smoothstep(0.12, 0.2, v)
purple = hsv_to_rgb(np.full_like(h, PURPLE_H), np.clip(s * 1.3 + 0.18, 0, 0.62), np.clip(v * 0.92, 0, 1))
rgb = rgb * (1 - teal[..., None]) + purple * teal[..., None]

def box_blur(A, r):
    # 三次方框模糊 ≈ 高斯（沿兩個軸，用累加和）
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(np.pad(A, [(r + 1, r) if a == ax else (0, 0) for a in range(A.ndim)], mode='edge'), axis=ax)
            hi = np.take(c, np.arange(2 * r + 1, c.shape[ax]), axis=ax)
            lo = np.take(c, np.arange(0, c.shape[ax] - 2 * r - 1), axis=ax)
            A = (hi - lo) / (2 * r + 1)
    return A

# ---- 皮膚：頭、兩隻手、腳 ----
def ball(c, r):
    d = np.sqrt((X - c[0]) ** 2 + (Y - c[1]) ** 2 + (Z - c[2]) ** 2)
    return 1 - smoothstep(r * 0.8, r, d)
region = smoothstep(0.40, 0.46, Z)                       # 頭（衣領以上）
region = np.maximum(region, ball((-0.40, -0.38, -0.10), 0.13))   # 拄拐杖的手
region = np.maximum(region, ball((0.31, -0.40, -0.36), 0.13))    # 抱書的手
region = np.maximum(region, 1 - smoothstep(-0.92, -0.88, Z))     # 腳
# 頭上不是皮膚的：白色眉毛鬍子（很白、幾乎沒彩度）、深色眼睛線條、藍綠色衣領
white = smoothstep(0.80, 0.88, v) * (1 - smoothstep(0.08, 0.15, s))
skin_c = (1 - white) * smoothstep(0.12, 0.2, v) * (1 - teal) * (smoothstep(0.0, 0.03, h) * (1 - smoothstep(0.17, 0.2, h)) + (h > 0.92))
skin_c = np.clip(skin_c, 0, 1)
w_skin = region * skin_c * have
# 細線（眼鏡、嘴巴、鼻子的線）要留下來：亮度減去局部平均，只取比周圍暗、而且邊緣很銳利的部分
lum = (pix[..., 0] * 0.3 + pix[..., 1] * 0.59 + pix[..., 2] * 0.11)
m = (region * have).astype(np.float64)
loc = box_blur(lum * m, 3) / np.maximum(box_blur(m, 3), 1e-3)
line = np.clip(-(lum - loc) - 0.025, 0, 0.4) * 2.2                  # 0..~0.9
# 依 3D 位置重畫：正面亮一點、頭頂後面暗一點、加一點水彩起伏和幾顆淡淡的斑
front = np.clip(-nor[..., 1], 0, 1); up = np.clip(nor[..., 2], 0, 1)
shade = 0.95 + 0.07 * front - 0.03 * up + 0.025 * noise3(pos, 7.0)
col = SKIN[None, None, :] * shade[..., None]
SPOTS = [(0.10, 0.10, 0.93, 0.045), (-0.14, 0.02, 0.92, 0.035), (0.0, 0.22, 0.86, 0.05),
         (0.22, 0.12, 0.82, 0.035), (-0.20, 0.20, 0.80, 0.04), (0.05, -0.12, 0.93, 0.03)]
for sx, sy, sz, sr in SPOTS:
    d = np.sqrt((X - sx) ** 2 + (Y - sy) ** 2 + (Z - sz) ** 2)
    k = (1 - smoothstep(sr * 0.5, sr, d)) * 0.7
    col = col * (1 - k[..., None]) + SKIN_SPOT[None, None, :] * shade[..., None] * k[..., None]
# 臉頰的腮紅
for cx_ in (-0.21, 0.21):
    d = np.sqrt((X - cx_) ** 2 + ((Z - 0.585) * 1.2) ** 2)
    k = (1 - smoothstep(0.03, 0.085, d)) * smoothstep(0.3, 0.6, front) * 0.45
    col = col * (1 - k[..., None]) + np.array([0.93, 0.62, 0.55]) * k[..., None]
# 眼鏡：臉正面那一圈的細線畫成深金色，其他細線（嘴、鼻）畫成深綠
gl = (1 - smoothstep(0.24, 0.28, np.abs(X))) * smoothstep(0.55, 0.57, Z) * (1 - smoothstep(0.73, 0.75, Z)) * smoothstep(0.4, 0.6, front)
ink = np.array([0.27, 0.30, 0.16]) * (1 - gl[..., None]) + np.array([0.62, 0.44, 0.16]) * gl[..., None]
kl = np.clip(line * (1 + 2.5 * gl) + 0.25 * gl * (line > 0.02), 0, 1)
col = col * (1 - kl[..., None]) + ink * kl[..., None]
rgb = rgb * (1 - w_skin[..., None]) + col * w_skin[..., None]
print("SKIN texels", int((w_skin > 0.5).sum()), "CLOAK texels", int((teal > 0.5).sum()))

pix[..., :3] = np.clip(rgb, 0, 1)
img.pixels.foreach_set(pix.ravel())
img.update(); img.pack()

# ================= 2. 新龜殼 =================
# 照正面設計圖量的：龜殼比身體還寬（正面看得到兩側和肩膀上面的殼緣），上緣到眉毛高、下緣到腰
SC = Vector((0.0, 0.15, 0.10))        # 圓頂中心（埋在背裡）
SR = Vector((0.76, 0.64, 0.58))       # 左右、往後、上下半徑
# 剖面 (s, h)：s = 離中軸的比例，h = 往後的比例；邊緣是一圈圓滾滾的厚緣
prof = [(0.0, -0.10), (0.90, -0.25), (0.97, -0.13), (1.03, -0.03), (1.04, 0.04), (1.0, 0.10)]
for k in range(1, 15):
    a = k / 15 * math.pi / 2
    prof.append((math.cos(a) * 0.985, 0.10 + 0.90 * math.sin(a) ** 0.85))
prof.append((0.0, 1.0))
NU = 72
shell = bmesh.new()
rings = []
for (ps, ph) in prof:
    ring = []
    for i in range(NU if ps > 0 else 1):
        u = 2 * math.pi * i / NU
        p = Vector((SC.x + SR.x * ps * math.cos(u), SC.y + SR.y * ph, SC.z + SR.z * ps * math.sin(u)))
        ring.append(shell.verts.new(p))
    rings.append(ring)
for a, b in zip(rings, rings[1:]):
    if len(a) == 1:
        for i in range(NU):
            shell.faces.new((a[0], b[(i + 1) % NU], b[i]))
    elif len(b) == 1:
        for i in range(NU):
            shell.faces.new((a[i], a[(i + 1) % NU], b[0]))
    else:
        for i in range(NU):
            shell.faces.new((a[i], a[(i + 1) % NU], b[(i + 1) % NU], b[i]))
bmesh.ops.recalc_face_normals(shell, faces=shell.faces)
# 貼圖座標：沿剖面的弧長攤平（頂點 0 → 圓頂和厚緣交界 0.86 → 厚緣外側 1.0），側面的緣甲才不會被拉長
pts = [Vector((ps * SR.x, ph * SR.y)) for ps, ph in prof]
J = 5
arc = [0.0] * len(prof)
for k in range(len(prof) - 2, J - 1, -1):
    arc[k] = arc[k + 1] + (pts[k] - pts[k + 1]).length
for k in range(J - 1, 0, -1):
    arc[k] = arc[k + 1] + (pts[k] - pts[k + 1]).length
r_uv = [0.0] * len(prof)
for k in range(J, len(prof)):
    r_uv[k] = 0.86 * arc[k] / arc[J]
for k in range(1, J):
    r_uv[k] = 0.86 + 0.14 * (arc[k] - arc[J]) / (arc[1] - arc[J])
r_uv[0] = 0.99   # 前面的底板（從正面殼緣縫隙看得到）用緣甲的顏色
ring_of = {v: k for k, ring in enumerate(rings) for v in ring}
uvs = shell.loops.layers.uv.new("UVMap")
for f in shell.faces:
    for l in f.loops:
        p = l.vert.co
        a = math.atan2((p.z - SC.z) / SR.z, (p.x - SC.x) / SR.x)
        r = r_uv[ring_of[l.vert]]
        l[uvs].uv = (0.5 + r * math.cos(a) / 2.3, 0.5 + r * math.sin(a) / 2.3)
shell_me = bpy.data.meshes.new("shell"); shell.to_mesh(shell_me); shell.free()
shell_ob = bpy.data.objects.new("shell", shell_me); bpy.context.collection.objects.link(shell_ob)

# 龜殼貼圖：中間一排脊甲、兩邊肋甲、外圈一圈緣甲；甲片中心亮、溝紋深、加年輪
TS = 1024
gy, gx = np.mgrid[0:TS, 0:TS]
U = (gx + 0.5) / TS; V = (gy + 0.5) / TS   # 注意：Blender 的 pixels 第 0 列是 v=0（下面）
nx = (U - 0.5) * 2.3; nz = (V - 0.5) * 2.3  # 正規化的龜殼平面座標（|n|=1 是外緣）
rr = np.sqrt(nx ** 2 + nz ** 2)
seeds = [(0, 0.46), (0, 0.0), (0, -0.46), (-0.42, 0.25), (0.42, 0.25), (-0.42, -0.25), (0.42, -0.25),
         (-0.74, 0.0), (0.74, 0.0), (-0.40, 0.70), (0.40, 0.70), (-0.40, -0.70), (0.40, -0.70), (0, 0.9), (0, -0.9)]
d1 = np.full(rr.shape, 9.0); d2 = np.full(rr.shape, 9.0); near = np.zeros(rr.shape, int)
for i, (sx, sz) in enumerate(seeds):
    d = np.sqrt(((nx - sx) * 1.0) ** 2 + ((nz - sz) * 1.05) ** 2)
    upd = d < d1
    d2 = np.where(upd, d1, np.minimum(d2, d)); d1 = np.where(upd, d, d1); near = np.where(upd, i, near)
edge = (d2 - d1)                          # 到甲片交界的距離（約）
plate = np.clip(1 - d1 / 0.36, 0, 1)      # 甲片中心 1 → 邊 0
SH = np.zeros((TS, TS, 3))
SH[:] = SHELL
SH = SH + (SHELL_LIGHT - SHELL) * (plate ** 1.5)[..., None]
rings_ = 0.5 + 0.5 * np.cos(d1 * 60.0)    # 年輪
SH *= (1 - 0.06 * rings_ * smoothstep(0.06, 0.14, d1))[..., None]
groove = 1 - smoothstep(0.018, 0.05, edge)
SH = SH * (1 - groove[..., None]) + SHELL_GROOVE * groove[..., None]
# 外圈緣甲（r 0.84..1）：一格一格
ang = np.arctan2(nz, nx)
seg = np.abs(((ang / (2 * np.pi) * 24) % 1) - 0.5)       # 0.5 在格線上
rim = smoothstep(0.82, 0.86, rr)
rim_col = SHELL_RIM * (0.95 + 0.1 * smoothstep(0.86, 1.0, rr))[..., None]
rim_groove = (smoothstep(0.42, 0.48, seg) + (1 - smoothstep(0.012, 0.03, np.abs(rr - 0.84)))).clip(0, 1)
rim_col = rim_col * (1 - rim_groove[..., None]) + SHELL_GROOVE * rim_groove[..., None]
SH = SH * (1 - rim[..., None]) + rim_col * rim[..., None]
SH *= (1 + 0.05 * np.sin(nx * 9.0 + nz * 5.0) * np.sin(nz * 7.0 - nx * 3.0))[..., None]   # 手繪感的深淺
simg = bpy.data.images.new("turtle_shell", TS, TS)
simg.pixels.foreach_set(np.concatenate([np.clip(SH, 0, 1), np.ones((TS, TS, 1))], -1).astype(np.float32).ravel())
simg.update(); simg.pack()

def tex_material(name, image, rough=0.85):
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    t = m.node_tree.nodes.new("ShaderNodeTexImage"); t.image = image
    m.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    return m
shell_me.materials.append(tex_material("PinShell", simg, 0.7))
for p in shell_me.polygons:
    p.use_smooth = True

# ================= 3. 新披風 =================
# 以身體中軸往外量「最外層」半徑 r(角度, 高度)，平滑後往外推一點，包成一整片沒有破洞的披風
Z_HEM, Z_TOP = -0.74, 0.44
NT, NZ = 96, 56
zs = np.linspace(Z_HEM, Z_TOP, NZ)
def theta0(z):  # 前面開口的半角（度）：肩膀處窄（貼著鬍子），手臂以下寬（袖子從前面伸出來）
    return 40.0 + 10.0 * (1 - smoothstep(0.12, 0.32, z))
R = np.zeros((NZ, NT)); TH = np.zeros((NZ, NT))
for j, z in enumerate(zs):
    t0 = theta0(z)
    for i in range(NT):
        th = t0 + (360 - 2 * t0) * i / (NT - 1)
        a = math.radians(th); d = Vector((math.sin(a), -math.cos(a), 0))
        hit = bvh.ray_cast(Vector((0, 0, z)) + d * 2.0, -d)
        R[j, i] = (2.0 - hit[3]) if hit[0] else 0.3
        TH[j, i] = th
# 太凸出去的（手、書、拐杖）壓回來，再做平滑
for j in range(NZ):
    back = np.median(R[j, NT // 4: 3 * NT // 4])
    R[j] = np.minimum(R[j], back + 0.06)
def blur(A, ax, sig):
    k = np.exp(-0.5 * (np.arange(-6, 7) / sig) ** 2); k /= k.sum()
    P = np.pad(A, [(6, 6) if a == ax else (0, 0) for a in range(2)], mode='edge')
    return np.apply_along_axis(lambda r: np.convolve(r, k, mode='valid'), ax, P)
R = blur(blur(R, 1, 2.2), 0, 1.8)
R = R + 0.025
# 鐘形：設計圖上披風在龜殼下面往外張開，下襬比龜殼還寬（正面量到的半寬）
BELL = np.interp(zs, [-0.74, -0.6, -0.4, -0.1, 0.1, 0.3], [0.84, 0.83, 0.79, 0.76, 0.64, 0.45])
# 鐘形只在兩側和前面張開（正面看的輪廓）；背後在龜殼下面只微微張開，不要像一個台階
TF = np.minimum(TH, 360 - TH)
T0 = np.array([theta0(z) for z in zs])[:, None]
side_w = (1 - 0.8 * smoothstep(110.0, 165.0, TF)) * (0.35 + 0.65 * smoothstep(T0 + 5.0, T0 + 40.0, TF))  # 前緣不要像門板一樣翹出去
R = np.maximum(R, R + (BELL[:, None] - R).clip(0) * side_w + 0.03 * smoothstep(-0.5, -0.74, zs)[:, None])
# 肩膀往脖子收（不要方方的肩膀）
CAP = np.interp(zs, [0.15, 0.3, 0.44], [0.9, 0.56, 0.42])
R = np.minimum(R, CAP[:, None])
# 披風不能蓋到龜殼：在龜殼後半部範圍裡，半徑限制在殼的裡面，再沿高度柔和過渡（殼下面才往外張開）
def shell_rmax(th, z, m):
    a_ = math.radians(th); sa, ca = math.sin(a_), math.cos(a_)
    if ca >= -0.05:
        return 9.0
    A = (sa / SR.x) ** 2 + (ca / SR.y) ** 2
    B = 2 * ca * SC.y / SR.y ** 2
    C = (SC.y / SR.y) ** 2 + ((z - SC.z) / SR.z) ** 2 - m * m
    disc = B * B - 4 * A * C
    if disc <= 0:
        return 9.0
    r_hi = (-B + math.sqrt(disc)) / (2 * A)
    r_c = (SC.y - 0.1 * SR.y) / (-ca)          # 殼的底板以後才算殼裡面
    return r_hi if r_hi > r_c else 9.0
RM = np.array([[shell_rmax(TH[j, i], zs[j], 0.9) for i in range(NT)] for j in range(NZ)])
RM2 = np.array([[shell_rmax(TH[j, i], zs[j], 0.97) for i in range(NT)] for j in range(NZ)])
R = np.minimum(R, RM)
R = blur(R, 0, 2.5)
R = np.minimum(R, RM2)
R[-3:] = R[-3:] - np.array([0.0, 0.005, 0.012])[:, None]           # 領口收一點
cl = bmesh.new()
grid = [[cl.verts.new((R[j, i] * math.sin(math.radians(TH[j, i])), -R[j, i] * math.cos(math.radians(TH[j, i])), zs[j]))
         for i in range(NT)] for j in range(NZ)]
uvc = cl.loops.layers.uv.new("UVMap")
for j in range(NZ - 1):
    for i in range(NT - 1):
        f = cl.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
        for l, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
            l[uvc].uv = (a / (NT - 1), b / (NZ - 1))
bmesh.ops.recalc_face_normals(cl, faces=cl.faces)
# 法線要朝外
f0 = cl.faces[len(cl.faces) // 2]
c0 = f0.calc_center_median()
if f0.normal.dot(Vector((c0.x, c0.y, 0))) < 0:
    bmesh.ops.reverse_faces(cl, faces=cl.faces)
cloak_me = bpy.data.meshes.new("cloak"); cl.to_mesh(cloak_me); cl.free()

# ---- 原本的破披風：在新披風範圍內往裡面壓（不會穿出來），掛在下襬下面的藍綠布條收上來 ----
uvl = body.data.uv_layers.active.data
vteal = np.zeros(len(body.data.vertices))
for poly in body.data.polygons:
    for li in poly.loop_indices:
        uv = uvl[li].uv
        tx = min(int(uv[0] % 1.0 * W), W - 1); ty = min(int(uv[1] % 1.0 * Hh), Hh - 1)
        vi = body.data.loops[li].vertex_index
        vteal[vi] = max(vteal[vi], teal[ty, tx])
key = lambda c: (round(c[0], 5), round(c[1], 5), round(c[2], 5))
kmax = {}
for i, vv in enumerate(body.data.vertices):
    k = key(vv.co); kmax[k] = max(kmax.get(k, 0.0), vteal[i])
def R_at(th, z):
    j = np.clip((z - Z_HEM) / (Z_TOP - Z_HEM) * (NZ - 1), 0, NZ - 1)
    j0 = int(min(j, NZ - 2)); fj = j - j0
    out = []
    for jj in (j0, j0 + 1):
        t0 = theta0(zs[jj])
        i = np.clip((th - t0) / (360 - 2 * t0) * (NT - 1), 0, NT - 1)
        i0 = int(min(i, NT - 2)); fi = i - i0
        out.append(R[jj, i0] * (1 - fi) + R[jj, i0 + 1] * fi)
    return out[0] * (1 - fj) + out[1] * fj
pushed = lifted = 0
for vv in body.data.vertices:
    x, y, z = vv.co
    tw = kmax[key(vv.co)]
    if tw > 0.3 and z < Z_HEM + 0.015:
        vv.co.z = z = Z_HEM + 0.015 + 0.004 * (z - Z_HEM)
        lifted += 1
    if z < Z_HEM - 0.02 or z > Z_TOP:
        continue
    th = math.degrees(math.atan2(x, -y)) % 360
    t0 = theta0(z)
    g = float(smoothstep(t0 + 1.0, t0 + 6.0, th) * smoothstep(t0 + 1.0, t0 + 6.0, 360 - th))
    if g <= 0:
        continue
    r = math.hypot(x, y)
    lim = R_at(th, min(max(z, Z_HEM), Z_TOP)) - 0.012
    if r > lim:
        k = (r - (r - lim) * g) / r
        vv.co.x = x * k; vv.co.y = y * k
        pushed += 1
body.data.update()
print("OLD CLOAK pushed", pushed, "lifted", lifted)
cloak_ob = bpy.data.objects.new("cloak", cloak_me); bpy.context.collection.objects.link(cloak_ob)

# 披風貼圖：紫色、水彩深淺、四周金邊、下襬一排金色菱形
CW, CH = 2048, 512
gy, gx = np.mgrid[0:CH, 0:CW]
U = (gx + 0.5) / CW; Vv = (gy + 0.5) / CH
circ = 2 * math.pi * 0.55 * (360 - 2 * 50) / 360    # 約略的周長（公尺）：讓金邊寬度一致
du = np.minimum(U, 1 - U) * circ                     # 到前緣的距離
dv_hem = Vv * (Z_TOP - Z_HEM); dv_top = (1 - Vv) * (Z_TOP - Z_HEM)
CC = np.zeros((CH, CW, 3)); CC[:] = CLOAK
fold = 0.5 + 0.5 * np.sin(U * 2 * np.pi * 9 + np.sin(Vv * 3.0) * 1.2)   # 直直的布摺
CC *= (0.92 + 0.10 * fold * smoothstep(0.1, 0.6, 1 - Vv) + 0.04 * np.sin(U * 61 + Vv * 17) * np.sin(Vv * 23))[..., None]
def band(d, a, b):
    return smoothstep(a - 0.004, a, d) * (1 - smoothstep(b, b + 0.004, d))
gold = np.maximum.reduce([band(du, 0.012, 0.034), band(dv_hem, 0.014, 0.036), band(dv_top, 0.008, 0.026)])
# 下襬的菱形
period = 0.16
cu = (U * circ) % period - period / 2
dia = (np.abs(cu) / 0.035 + np.abs(dv_hem - 0.075) / 0.025)
gold = np.maximum(gold, (1 - smoothstep(0.85, 1.0, dia)) * smoothstep(0.07, 0.1, du))
inner = (1 - smoothstep(0.6, 0.75, dia)) * smoothstep(0.07, 0.1, du)
gold_col = GOLD * (0.95 + 0.08 * np.sin(U * 300))[..., None]
CC = CC * (1 - gold[..., None]) + gold_col * gold[..., None]
CC = CC * (1 - inner[..., None]) + CLOAK_DARK * inner[..., None]
edge_dark = (1 - smoothstep(0.0, 0.012, np.minimum(du, dv_hem)))
CC = CC * (1 - 0.35 * edge_dark[..., None])
cimg = bpy.data.images.new("turtle_cloak", CW, CH)
cimg.pixels.foreach_set(np.concatenate([np.clip(CC, 0, 1), np.ones((CH, CW, 1))], -1).astype(np.float32).ravel())
cimg.update(); cimg.pack()
cloak_me.materials.append(tex_material("PinCloak", cimg))
lin = bpy.data.materials.new("PinCloakLining"); lin.use_nodes = True
lin.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*(CLOAK_DARK ** 2.2), 1)
lin.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
cloak_me.materials.append(lin)
for p in cloak_me.polygons:
    p.use_smooth = True
bpy.context.view_layer.objects.active = cloak_ob
sol = cloak_ob.modifiers.new("solid", 'SOLIDIFY')
sol.thickness = 0.016; sol.offset = 1.0; sol.use_rim = True; sol.material_offset = 1; sol.material_offset_rim = 0
bpy.ops.object.select_all(action='DESELECT'); cloak_ob.select_set(True)
bpy.ops.object.modifier_apply(modifier="solid")

# ================= 3c. 裡面長袍的下襬：破破的碎布換成一圈完整的奶油色裙襬 =================
SK0, SK1 = -0.885, -0.70          # 裙襬從下面到上面（上緣藏在披風裡）
CANE = (300.0, 336.0)             # 拐杖所在的角度：量半徑時跳過、也不壓
NS, NZS = 120, 14
zk = np.linspace(SK0, SK1, NZS)
RS = np.zeros((NZS, NS))
for j, z in enumerate(zk):
    for i in range(NS):
        a = 2 * math.pi * i / NS; d = Vector((math.sin(a), -math.cos(a), 0))
        hit = bvh.ray_cast(Vector((0, 0, z)) + d * 2.0, -d)
        RS[j, i] = (2.0 - hit[3]) if hit[0] else 0.3
    th_deg = np.arange(NS) * 360.0 / NS
    ok = ~((th_deg > CANE[0] - 6) & (th_deg < CANE[1] + 6))
    med = np.median(RS[j, ok])
    RS[j] = np.clip(RS[j], med - 0.06, med + 0.03)
    RS[j, ~ok] = med
RS = np.maximum.accumulate(RS[::-1], axis=0)[::-1]           # 往下只會越來越寬（不會往內縮）
P2 = np.pad(RS, [(0, 0), (8, 8)], mode='wrap')
k = np.exp(-0.5 * (np.arange(-8, 9) / 3.0) ** 2); k /= k.sum()
RS = np.array([np.convolve(r, k, mode='valid') for r in P2])
RS = blur(RS, 0, 1.2)
RS = RS + 0.012 + 0.02 * smoothstep(SK0 + 0.08, SK0, zk)[:, None]
sk = bmesh.new()
sg = [[sk.verts.new((RS[j, i] * math.sin(2 * math.pi * i / NS), -RS[j, i] * math.cos(2 * math.pi * i / NS), zk[j]))
       for i in range(NS)] for j in range(NZS)]
uvk = sk.loops.layers.uv.new("UVMap")
for j in range(NZS - 1):
    for i in range(NS):
        i2 = (i + 1) % NS
        f = sk.faces.new((sg[j][i], sg[j][i2], sg[j + 1][i2], sg[j + 1][i]))
        for l, (a, b) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
            l[uvk].uv = (a / NS, b / (NZS - 1))
sk.faces.ensure_lookup_table(); f0 = sk.faces[0]; c0 = f0.calc_center_median()
if f0.normal.dot(Vector((c0.x, c0.y, 0))) < 0:
    bmesh.ops.reverse_faces(sk, faces=sk.faces)
skirt_me = bpy.data.meshes.new("skirt"); sk.to_mesh(skirt_me); sk.free()
skirt_ob = bpy.data.objects.new("skirt", skirt_me); bpy.context.collection.objects.link(skirt_ob)
KW, KH = 2048, 256
gy, gx = np.mgrid[0:KH, 0:KW]
U = (gx + 0.5) / KW; Vv = (gy + 0.5) / KH
dz = Vv * (SK1 - SK0)
CREAM = np.array([0.94, 0.88, 0.73])
KC = np.zeros((KH, KW, 3)); KC[:] = CREAM
KC *= (0.94 + 0.06 * np.sin(U * 2 * np.pi * 26 + 0.8 * np.sin(U * 40)))[..., None]   # 細細的直摺
gb = np.maximum(band(dz, 0.012, 0.024), band(dz, 0.032, 0.038))
KC = KC * (1 - gb[..., None]) + GOLD * gb[..., None]
KC *= (1 - 0.25 * (1 - smoothstep(0.0, 0.008, dz)))[..., None]
kimg = bpy.data.images.new("turtle_robe", KW, KH)
kimg.pixels.foreach_set(np.concatenate([np.clip(KC, 0, 1), np.ones((KH, KW, 1))], -1).astype(np.float32).ravel())
kimg.update(); kimg.pack()
skirt_me.materials.append(tex_material("PinRobe", kimg))
skirt_me.materials.append(lin)   # 裡面看不到，用披風裡布的材質就好
for p_ in skirt_me.polygons:
    p_.use_smooth = True
bpy.context.view_layer.objects.active = skirt_ob
sol = skirt_ob.modifiers.new("solid", 'SOLIDIFY')
sol.thickness = 0.01; sol.offset = 1.0; sol.use_rim = True; sol.material_offset = 1; sol.material_offset_rim = 0
bpy.ops.object.select_all(action='DESELECT'); skirt_ob.select_set(True)
bpy.ops.object.modifier_apply(modifier="solid")
# 原本的碎布下襬壓進新裙襬裡（拐杖那邊不動）
pushed = 0
for vv in body.data.vertices:
    x, y, z = vv.co
    if z < SK0 - 0.012 or z > SK1:
        continue
    th = math.degrees(math.atan2(x, -y)) % 360
    if CANE[0] - 4 < th < CANE[1] + 4:
        continue
    jf = np.clip((z - SK0) / (SK1 - SK0) * (NZS - 1), 0, NZS - 1.001); j0 = int(jf); fj = jf - j0
    ii = th / 360 * NS; i0 = int(ii) % NS; i1 = (i0 + 1) % NS; fi = ii - int(ii)
    lim = ((RS[j0, i0] * (1 - fi) + RS[j0, i1] * fi) * (1 - fj) + (RS[j0 + 1, i0] * (1 - fi) + RS[j0 + 1, i1] * fi) * fj) - 0.008
    r = math.hypot(x, y)
    if r > lim:
        vv.co.x = x * lim / r; vv.co.y = y * lim / r; pushed += 1
    if z < SK0 + 0.004 and r > lim - 0.05:
        vv.co.z = SK0 + 0.004     # 掛在新裙襬下面的碎布尖收上來
body.data.update()
print("ROBE hem pushed", pushed)

# ================= 3d. 胸前兩顆金色圓扣（披風前緣） =================
CS = 256
gy, gx = np.mgrid[0:CS, 0:CS]
cu = (gx + 0.5) / CS * 2 - 1; cv = (gy + 0.5) / CS * 2 - 1
rr2 = np.sqrt(cu ** 2 + cv ** 2)
GC = np.zeros((CS, CS, 3)); GC[:] = GOLD * 1.05
GC *= (0.85 + 0.25 * (1 - rr2))[..., None]
ring = (1 - smoothstep(0.03, 0.08, np.abs(rr2 - 0.82)))
dia = (np.abs(cu) + np.abs(cv) * 0.75)
dd = (1 - smoothstep(0.42, 0.48, dia)) * smoothstep(0.30, 0.36, dia) + (1 - smoothstep(0.12, 0.18, dia))
GC = GC * (1 - 0.45 * np.clip(ring + dd, 0, 1))[..., None]
gimg = bpy.data.images.new("turtle_clasp", CS, CS)
gimg.pixels.foreach_set(np.concatenate([np.clip(GC, 0, 1), np.ones((CS, CS, 1))], -1).astype(np.float32).ravel())
gimg.update(); gimg.pack()
clasp_mat = tex_material("PinClasp", gimg, 0.5)
clasps = []
for sx in (-1, 1):
    zc_ = 0.2
    th = theta0(zc_) + 2.0
    a_ = math.radians(th if sx > 0 else 360 - th)
    rc = R_at(th, zc_) + 0.03
    pos_ = Vector((rc * math.sin(a_), -rc * math.cos(a_), zc_))
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.06, depth=0.025, location=pos_)
    ob = bpy.context.active_object
    nrm = Vector((math.sin(a_), -math.cos(a_), 0.0))
    ob.rotation_euler = nrm.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    me = ob.data
    me.uv_layers.new(name="UVMap") if not me.uv_layers else None
    bm_ = bmesh.new(); bm_.from_mesh(me); uvl_ = bm_.loops.layers.uv.active
    for f in bm_.faces:
        for l in f.loops:
            c = l.vert.co
            loc = Vector((c.dot(Vector((math.cos(a_), math.sin(a_), 0))), c.z, 0)) / 0.06
            l[uvl_].uv = (0.5 + 0.5 * loc.x, 0.5 + 0.5 * loc.y)
    bm_.to_mesh(me); bm_.free()
    me.materials.clear(); me.materials.append(clasp_mat)
    for p_ in me.polygons:
        p_.use_smooth = False
    clasps.append(ob)

# ================= 4. 合併、輸出 =================
bpy.ops.object.select_all(action='DESELECT')
for o in (body, shell_ob, cloak_ob, skirt_ob, *clasps):
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
print("VERTS", len(body.data.vertices), "MATS", [m.name for m in body.data.materials])
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_image_format='JPEG',
                          export_jpeg_quality=92, export_yup=True, use_selection=False)
print("EXPORTED", OUT)

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'FLAT'; sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 600; sc.render.resolution_y = 600
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.5, 0.5, 0.5)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.3
    for nm, d in {"front": (0, -1, 0), "back": (0, 1, 0), "left": (1, 0, 0), "right": (-1, 0, 0),
                  "q34": (0.7, -0.7, 0.25), "q34b": (-0.7, 0.7, 0.3)}.items():
        d = Vector(d).normalized(); cam.location = d * 5
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(PREVIEW, f"fix_{nm}.png"); bpy.ops.render.render(write_still=True)
