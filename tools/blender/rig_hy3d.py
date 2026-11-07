# 混元 3D 生成的土撥鼠 → 修腳、校色、接上 Kenney 人型骨架（含全部動畫）→ 匯出遊戲用 GLB
# 用法：blender -b --factory-startup --python tools/blender/rig_hy3d.py -- <kenney.glb> <hy3d.glb> <out.glb> [gopher|rabbit]
# 座標：Blender Z 向上、角色面向 -Y。模型先縮放到高 0.74（和 Kenney 骨架同尺度）。
import bpy, bmesh, sys, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion

args = sys.argv[sys.argv.index("--") + 1:]
KENNEY, SRC, OUT = args[0], args[1], args[2]
PROFILE = args[3] if len(args) > 3 else "gopher"
# 每隻角色的參數。座標都是正規化後（腳底 z=0、總高 H）的 Blender 座標。
# zones：多視圖多出來的臉要蓋掉的橢球 (|x| 中心, y, z, rx, ry, rz)，左右對稱
PROFILES = {
    "gopher": dict(
        H=0.74, feet=True,
        curves={0: [(0, 0), (65, 60), (120, 160), (253, 245), (255, 252)],
                1: [(0, 0), (48, 35), (92, 120), (241, 218), (255, 248)],
                2: [(0, 0), (18, 7), (32, 50), (201, 169), (255, 232)]},
        zones=[(0.2, -0.015, 0.48, 0.13, 0.085, 0.06)],
        neck=0.39, hip=0.105, foot=(0.135, -0.03), foot_y=(0.095, 0.135),  # 腳跟在 y≈0.09，後面是肚子
        smooth_legs=True, thigh_y=(0.04, 0.13), thigh_z=(0.06, 0.11),  # 腿的權重只在腳印上，再沿著網格模糊（走路時肚子不會被撕開）
        shoulder=(0.215, -0.05, 0.35), paw=(0.245, -0.07, 0.175), arm_out=(0.2, 0.232),
        arm_z=(0.15, 0.37)),
    "rabbit": dict(
        H=1.04, feet=False,
        curves={0: [(0, 0), (70, 80), (130, 160), (155, 195), (230, 240), (255, 252)],
                1: [(0, 0), (60, 68), (114, 140), (171, 165), (255, 235)],
                2: [(0, 0), (40, 45), (65, 85), (125, 132), (255, 230)]},
        zones=[(0.2, 0.0, 0.53, 0.12, 0.075, 0.07),     # 頭兩側的小臉
               (0.0, 0.22, 0.53, 0.17, 0.08, 0.075)],   # 後腦的鋸齒嘴（貼圖上下色交界一起柔化）
        thigh_z=(0.07, 0.105),  # 外套下襬不要被腿拉
        geo=[(0.2, 0.0, 0.53, 0.12, 0.075, 0.07),
             (0.0, 0.22, 0.53, 0.15, 0.05, 0.03)],      # 鋸齒刻痕只磨一條細帶
        neck=0.405, hip=0.1, foot=(0.085, 0.0),
        shoulder=(0.17, 0.0, 0.37), paw=(0.215, 0.0, 0.2), arm_out=(0.165, 0.195),
        arm_z=(0.16, 0.39)),
    "wolf": dict(
        H=0.9, feet=False, curves=None, zones=[],
        neck=0.495, hip=0.09, foot=(0.11, -0.03),
        shoulder=(0.215, -0.03, 0.47), paw=(0.25, -0.05, 0.17), arm_out=(0.19, 0.225),
        arm_z=(0.14, 0.49), thigh_z=(0.08, 0.14)),
}
P = PROFILES[PROFILE]
H = P["H"]

def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- 1. Kenney 骨架與動畫 ----------
bpy.ops.import_scene.gltf(filepath=KENNEY)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for o in list(bpy.data.objects):
    if o.type == 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
arm.name = PROFILE.capitalize()
arm.data.pose_position = 'REST'

# ---------- 2. 生成的模型：合併、放到原點、縮放 ----------
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SRC, merge_vertices=True, import_shading="SMOOTH")
new = [o for o in bpy.data.objects if o not in before]
meshes = [o for o in new if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
mesh = bpy.context.view_layer.objects.active
mesh.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in new:
    if o != mesh and o.name in bpy.data.objects:
        bpy.data.objects.remove(o, do_unlink=True)
mesh.name = PROFILE + "-mesh"

co = np.array([v.co[:] for v in mesh.data.vertices])
cx = (co[:, 0].min() + co[:, 0].max()) / 2
zmin, zmax = co[:, 2].min(), co[:, 2].max()
s = H / (zmax - zmin)
co[:, 0] -= cx
co[:, 2] -= zmin
co *= s
print("SCALE", round(s, 4), "orig height", round(zmax - zmin, 3))

# ---------- 3. 修腳：後半段多出來的兩個肉墊抬平到肚子底部 ----------
# 原模型每邊是一整條長腳底（y -0.12 ~ +0.13）。前半（有腳趾）保留成一隻腳，
# 腳印是橢圓：腳跟圓圓地收起來，不會像被斜斜削掉一塊；橢圓外面才抬到肚子底部。
LIFT = 0.049                 # 肚子底部離地高度
FOOT_CX, FOOT_CY = 0.152, -0.05   # 原本前腳的腳印中心（左右對稱）
FOOT_RX, FOOT_RY = 0.08, 0.062    # 腳印半徑：腳跟收在原本前腳和肉墊之間的摺痕（y≈+0.01）
FOOT_WIDEN = 1.12                 # 腳稍微加寬（以腳的中線為準）
if P["feet"]:
    for i in range(len(co)):
        x, y, z = co[i]
        w = (1.0 - smoothstep(0.045, 0.085, z)) * (1.0 - smoothstep(0.08, 0.12, y)) * smoothstep(0.03, 0.07, abs(x))
        if w > 0:
            sx = 1.0 if x > 0 else -1.0
            co[i, 0] = sx * (FOOT_CX + (abs(x) - FOOT_CX) * (1.0 + (FOOT_WIDEN - 1.0) * w))
moved = []
for i in (range(len(co)) if P["feet"] else []):
    x, y, z = co[i]
    dx = (abs(x) - FOOT_CX) / FOOT_RX
    dy = max(y - FOOT_CY, 0.0) / FOOT_RY   # 前面（腳趾那頭）不動
    d = (dx * dx + dy * dy) ** 0.5
    t = min(max((d - 0.85) / 0.4, 0.0), 1.0)
    # 肚子底部是碗狀（中間低 3.4 cm、兩側約 7 cm）：抬到碗面上，才不會留下一片平板
    bowl = 0.034 + 0.04 * (abs(x) / 0.23) ** 2
    L = bowl * (1.0 - (1.0 - t * t) ** 0.5)          # 四分之一圓：側面看腳跟是圓弧，不是斜切面
    gate = smoothstep(-0.035, 0.0, y) * (1.0 - smoothstep(0.13, 0.16, y))   # 不動到腳趾和尾巴
    if gate <= 0.0:
        continue
    # 肉墊往外凸出肚子的部分：往中間收進肚子底下（只收低處，越低收越多）
    w = gate * t * (1.0 - smoothstep(0.05, 0.085, z))
    nx = x * (1.0 - 0.3 * w)
    nz = z + (max(z, L) - z) * gate
    if nz != z or nx != x:
        co[i, 0] = nx
        co[i, 2] = nz
        moved.append(i)
# 參考派派兔／派派狼：腳長約身體前後厚度的 40–50%，腳的中心在身體重心下面（稍微偏前）。
# 原本的前腳太短又太前面：整隻腳往後移 3 cm，再往後拉長 1.4 倍
# （腳長 0.135 → 0.19，腳尖 -0.10、腳跟 +0.09，中心落在身體重心下）。
# 拉的是有厚度的前腳本身，腳跟還是圓的；後面的肚子跟著往後讓開。
TOE_Y, HEEL_Y, STRETCH, BACK = -0.129, 0.008, 1.4, 0.03
SHIFT = BACK + (HEEL_Y - TOE_Y) * (STRETCH - 1.0)
for i in (range(len(co)) if P["feet"] else []):
    x, y, z = co[i]
    w = (1.0 - smoothstep(0.05, 0.095, z)) * smoothstep(0.03, 0.07, abs(x))
    if w <= 0:
        continue
    if y <= HEEL_Y:
        dy = BACK + (max(y, TOE_Y) - TOE_Y) * (STRETCH - 1.0)
    else:
        dy = SHIFT * (1.0 - smoothstep(HEEL_Y, HEEL_Y + 0.13, y))
    co[i, 1] = y + dy * w
mesh.data.vertices.foreach_set("co", co.ravel())
mesh.data.update()
# 被抬平的地方做幾次平滑，避免出現平台和稜角
bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
# 抬平的區域往外擴 4 圈，權重由內往外遞減：把抬平後的平板邊緣「融」進肚子，不留切口
ring = {i: 1.0 for i in moved}
front = set(moved)
for k in range(4):
    nxt = set()
    for i in front:
        for e in bm.verts[i].link_edges:
            j = e.other_vert(bm.verts[i]).index
            if j not in ring:
                nxt.add(j)
    for j in nxt:
        ring[j] = 0.8 - 0.18 * k
    front = nxt
region = [bm.verts[i] for i in ring]
def welded_smooth(verts, weight, iters, taubin=True):
    # 貼圖接縫處同一位置有多個頂點：以位置合併後再平滑，才不會裂開
    key = lambda co: (round(co.x, 5), round(co.y, 5), round(co.z, 5))
    groups = {}
    for v in verts:
        groups.setdefault(key(v.co), []).append(v)
    allk = {}
    for v in bm.verts:
        allk.setdefault(key(v.co), v.co.copy())
    nbs = {k: set() for k in groups}
    for k, vs in groups.items():
        for v in vs:
            for e in v.link_edges:
                nbs[k].add(key(e.other_vert(v).co))
        nbs[k].discard(k)
    pos = dict(allk)
    w = {k: weight(vs[0]) for k, vs in groups.items()}
    for it in range(iters):
        f = (0.5 if it % 2 == 0 else -0.53) if taubin else 0.5
        newp = {}
        for k in groups:
            if nbs[k]:
                avg = sum((pos[n] for n in nbs[k]), Vector()) / len(nbs[k])
                newp[k] = pos[k] + (avg - pos[k]) * f * w[k]
        pos.update(newp)
    for k, vs in groups.items():
        for v in vs:
            v.co = pos[k]

def zone_r(x, y, z):  # 到最近一個（要磨平幾何的）橢球區的正規化距離
    return min([((((abs(x) - zx) / rx) ** 2 + ((y - zy) / ry) ** 2 + ((z - zz) / rz) ** 2) ** 0.5)
                for zx, zy, zz, rx, ry, rz in P.get("geo", P["zones"])] + [9.0])
welded_smooth(region, lambda v: ring.get(v.index, 0.0), 45, taubin=False)  # 腳底抬平處：多磨幾次，平板融進肚子、腳跟變圓
welded_smooth(region, lambda v: ring.get(v.index, 0.0), 10)
def _wf(v):  # 多出的小臉：一般 Laplacian 多次把凹痕填平，再 Taubin 修飾
    return 1 - smoothstep(0.8, 1.15, zone_r(*v.co))
core = [v for v in bm.verts if _wf(v) > 0]
welded_smooth(core, _wf, 90, taubin=False)
welded_smooth(core, _wf, 20)
bm.to_mesh(mesh.data); bm.free()
print("FEET lifted verts", len(moved), "face-zone smoothed", len(core))

# ---------- 4. 校色：依參考圖的主要色塊（毛、奶油、背心、深色）逐通道對應 ----------
img = None
for m in mesh.data.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                img = n.image
if img:
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    curves = P["curves"] or {}  # (貼圖值, 參考圖值)，0..255，sRGB
    for ch, pts in curves.items():
        xs = np.array([p[0] for p in pts]) / 255.0
        ys = np.array([p[1] for p in pts]) / 255.0
        px[:, ch] = np.interp(px[:, ch], xs, ys)
    # 多視圖生成時，側面圖的臉被投影到頭的兩側（多出一對小眼睛＋嘴）：
    # 逐貼圖像素算出 3D 位置，在橢圓區域內柔和地蓋成周圍毛色
    W, Hh = img.size
    pix = px.reshape(Hh, W, 4)
    uvl = mesh.data.uv_layers.active.data
    vco = np.array([v.co[:] for v in mesh.data.vertices])
    rmap = np.full((Hh, W), 9.0, dtype=np.float32) if P["zones"] else None  # 橢圓正規化距離
    zmap = np.zeros((Hh, W), dtype=np.float32)       # 該像素的 3D 高度（毛色上淺下深，要跟著漸層）
    yy, xx = np.mgrid[0:Hh, 0:W]
    def ell(Q):
        out = None
        for zx, zy, zz, rx, ry, rz in P["zones"]:
            r = np.sqrt(((np.abs(Q[..., 0]) - zx) / rx) ** 2 + ((Q[..., 1] - zy) / ry) ** 2 + ((Q[..., 2] - zz) / rz) ** 2)
            out = r if out is None else np.minimum(out, r)
        return out
    for poly in (mesh.data.polygons if P["zones"] else []):
        pv = vco[list(poly.vertices)]
        c = pv.mean(0)
        if ell(c) > 1.6:
            continue
        uv = np.array([uvl[li].uv[:] for li in poly.loop_indices]) * [W, Hh]
        for k in range(1, len(uv) - 1):
            tri = np.array([uv[0], uv[k], uv[k + 1]]); P3 = pv[[0, k, k + 1]]
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
            inside = (l1 >= -0.05) & (l2 >= -0.05) & (l3 >= -0.05)
            Q = l1[..., None] * P3[0] + l2[..., None] * P3[1] + l3[..., None] * P3[2]
            r = ell(Q)
            sub = rmap[y0:y1 + 1, x0:x1 + 1]; zsub = zmap[y0:y1 + 1, x0:x1 + 1]
            better = inside & (r < sub)
            sub[better] = r[better]; zsub[better] = Q[..., 2][better]
    for _ in (range(6) if P["zones"] else []):  # 往外擴幾格，蓋到 UV 島邊緣的填充像素
        r2 = rmap.copy(); z2 = zmap.copy()
        for sl_dst, sl_src in (((slice(1, None), slice(None)), (slice(None, -1), slice(None))),
                               ((slice(None, -1), slice(None)), (slice(1, None), slice(None))),
                               ((slice(None), slice(1, None)), (slice(None), slice(None, -1))),
                               ((slice(None), slice(None, -1)), (slice(None), slice(1, None)))):
            b = rmap[sl_src] < r2[sl_dst]
            r2[sl_dst][b] = rmap[sl_src][b]; z2[sl_dst][b] = zmap[sl_src][b]
        rmap, zmap = r2, z2
    ring = ((rmap > 1.05) & (rmap < 1.5)) if P["zones"] else None
    if ring is not None and ring.any():
        # 用周圍一圈的毛色對高度做線性回歸 → 填色帶有上下漸層，不會變成一塊色斑
        rc = pix[ring][:, :3]; rz = zmap[ring]
        A = np.stack([np.ones_like(rz), rz], 1)
        coef, *_ = np.linalg.lstsq(A, rc, rcond=None)
        fill = np.median(rc, axis=0)
        sel = rmap < 1.15
        fz = (coef[0] + zmap[sel][:, None] * coef[1]).clip(0, 1)
        t = np.clip((rmap[sel] - 0.75) / 0.35, 0, 1)
        wgt = (1 - t * t * (3 - 2 * t))[:, None]
        pix[sel, :3] = pix[sel, :3] * (1 - wgt) + fz * wgt
        px = pix.reshape(-1, 4)
        print("SIDE FACE repainted:", int((rmap < 1.1).sum()), "px, fill", (fill * 255).round())
    img.pixels.foreach_set(px.ravel())
    img.update()
    img.pack()
    print("COLOR corrected", img.name, tuple(img.size))

# ---------- 5. 骨架對齊這隻土撥鼠的比例 ----------
NECK_Z, HIP_Z = P["neck"], P["hip"]
FOOT_X, FOOT_Y = P["foot"]
SHOULDER = Vector(P["shoulder"])
PAW = Vector(P["paw"])

# 手臂：靜止姿勢改成 idle 第 0 格（自然下垂），動畫的旋轉要一起換算
def all_fcurves(action):
    try:
        if len(action.fcurves):
            return list(action.fcurves)
    except AttributeError:
        pass
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out

def quat_curves(action, bone):
    path = f'pose.bones["{bone}"].rotation_quaternion'
    fc = {f.array_index: f for f in all_fcurves(action) if f.data_path == path}
    return fc if len(fc) == 4 else None

idle = bpy.data.actions.get("idle")
q_idle = {}
for b in ("arm-left", "arm-right"):
    fc = quat_curves(idle, b)
    q_idle[b] = Quaternion([fc[i].evaluate(0.0) for i in range(4)]).normalized()

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
def move(name, head):
    b = eb[name]
    d = Vector(head) - b.head
    b.head += d; b.tail += d
move("torso", (0, -0.01, HIP_Z))
move("leg-left", (FOOT_X, FOOT_Y, HIP_Z))
move("leg-right", (-FOOT_X, FOOT_Y, HIP_Z))
move("head", (0, -0.01, NECK_Z))
for b, sx in (("arm-left", 1), ("arm-right", -1)):
    e = eb[b]
    L = e.length
    m = e.matrix @ q_idle[b].to_matrix().to_4x4()
    m.translation = Vector((sx * SHOULDER.x, SHOULDER.y, SHOULDER.z))
    e.matrix = m
    e.length = L
bpy.ops.object.mode_set(mode='OBJECT')

# 所有動畫裡的手臂旋轉：q' = q_idle⁻¹ · q（輸出到 glTF 的絕對旋轉不變）
fixed = 0
for act in bpy.data.actions:
    for b in ("arm-left", "arm-right"):
        fc = quat_curves(act, b)
        if not fc:
            continue
        inv = q_idle[b].inverted()
        n = len(fc[0].keyframe_points)
        if any(len(fc[i].keyframe_points) != n for i in range(4)):
            print("WARN uneven keys", act.name, b)
            continue
        for k in range(n):
            q = Quaternion([fc[i].keyframe_points[k].co[1] for i in range(4)])
            q2 = inv @ q
            for i in range(4):
                kp = fc[i].keyframe_points[k]
                dv = q2[i] - kp.co[1]
                kp.co[1] = q2[i]
                kp.handle_left[1] += dv
                kp.handle_right[1] += dv
        for i in range(4):
            fc[i].update()
        fixed += 1
print("ARM curves fixed", fixed)

# 走路／跑步的抬腿幅度放大：腳短又大，原本 Kenney 的擺幅看起來幾乎沒動
LEG_AMP = P.get("leg_amp", 1.7)
for act in bpy.data.actions:
    if act.name not in ("walk", "sprint"):
        continue
    for b in ("leg-left", "leg-right"):
        fc = quat_curves(act, b)
        if not fc:
            continue
        n = len(fc[0].keyframe_points)
        if any(len(fc[i].keyframe_points) != n for i in range(4)):
            continue
        for k in range(n):
            q = Quaternion([fc[i].keyframe_points[k].co[1] for i in range(4)]).normalized()
            qp = q.copy()
            if qp.w < 0:  # 取最短的那一邊（角度 ≤ 180°）再放大
                qp.negate()
            ax, ang = qp.to_axis_angle()
            q2 = Quaternion(ax, ang * LEG_AMP)
            if q2.dot(q) < 0:
                q2.negate()
            for i in range(4):
                kp = fc[i].keyframe_points[k]
                dv = q2[i] - kp.co[1]
                kp.co[1] = q2[i]; kp.handle_left[1] += dv; kp.handle_right[1] += dv
        for i in range(4):
            fc[i].update()
        print("LEG amp", act.name, b, n, "keys")

# ---------- 6. 權重：依部位分配，交界處平滑過渡 ----------
co = np.array([v.co[:] for v in mesh.data.vertices])
groups = {n: mesh.vertex_groups.new(name=n) for n in ("root", "torso", "head", "leg-left", "leg-right", "arm-left", "arm-right")}
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length, t
W_ALL = []
for i, (x, y, z) in enumerate(co):
    p = Vector((x, y, z))
    w = {}
    w["head"] = smoothstep(NECK_Z - 0.015, NECK_Z + 0.02, z)
    # 腳掌全歸腿；往上到大腿外側也跟著腿（中間肚子不跟，免得被左右扯開）
    foot = (1.0 - smoothstep(0.055, 0.09, z)) * (1.0 - smoothstep(*P.get("foot_y", (0.1, 0.16)), y))  # 尾巴（和腳跟後面的肚子）不算腳
    if P.get("smooth_legs"):
        foot *= smoothstep(0.035, 0.08, abs(x))   # 肚子正中間的底部不跟腳走
    thigh = (1.0 - smoothstep(*P.get("thigh_z", (0.1, 0.17)), z)) * smoothstep(0.03, 0.08, abs(x))         * (1.0 - smoothstep(*P.get("thigh_y", (FOOT_Y + 0.03, FOOT_Y + 0.08)), y))
    legs = max(foot, thigh)
    side = smoothstep(-0.03, 0.03, x)
    w["leg-left"] = legs * side
    w["leg-right"] = legs * (1 - side)
    for b, sx in (("arm-left", 1), ("arm-right", -1)):
        a = Vector((sx * SHOULDER.x, SHOULDER.y, SHOULDER.z))
        pb = Vector((sx * PAW.x, PAW.y, PAW.z))
        d, t = seg_dist(p, a, pb)
        out = smoothstep(P["arm_out"][0], P["arm_out"][1], sx * x)
        near = 1.0 - smoothstep(0.055, 0.08, d)
        za, zb = P["arm_z"]
        zwin = smoothstep(za, za + 0.025, z) * (1.0 - smoothstep(zb - 0.025, zb, z))
        w[b] = out * near * zwin
    tot = sum(w.values())
    if tot > 1.0:
        for k in w:
            w[k] /= tot
        tot = 1.0
    w["torso"] = 1.0 - tot
    W_ALL.append(w)

# 腿的權重沿著網格模糊（同位置的頂點合併計算）：交界變寬變平滑，肚子跟著腿慢慢彎，不會撕開
if P.get("smooth_legs"):
    bm = bmesh.new(); bm.from_mesh(mesh.data); bm.verts.ensure_lookup_table()
    key = lambda v: (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
    kid = {}
    vk = [kid.setdefault(key(v), len(kid)) for v in bm.verts]
    nb = [set() for _ in kid]
    for e in bm.edges:
        a, b = vk[e.verts[0].index], vk[e.verts[1].index]
        if a != b:
            nb[a].add(b); nb[b].add(a)
    bm.free()
    for g in ("leg-left", "leg-right"):
        val = np.zeros(len(kid)); zk = np.zeros(len(kid))
        for i, w in enumerate(W_ALL):
            val[vk[i]] = max(val[vk[i]], w[g]); zk[vk[i]] = co[i][2]
        pin = (zk < 0.03) & (val > 0.5)        # 腳底一定跟腳走
        nbl = [list(n) for n in nb]
        for it in range(25):
            new = np.array([val[n].mean() if n else val[k] for k, n in enumerate(nbl)])
            val = np.where(pin, val, 0.5 * val + 0.5 * new)
        for i, w in enumerate(W_ALL):
            w[g] = float(val[vk[i]])
    for i, w in enumerate(W_ALL):
        legs = w["leg-left"] + w["leg-right"]
        others = w["head"] + w["arm-left"] + w["arm-right"]
        if legs + others > 1.0:
            f = (1.0 - others) / legs if legs > 0 else 0
            w["leg-left"] *= f; w["leg-right"] *= f
        w["torso"] = max(0.0, 1.0 - w["leg-left"] - w["leg-right"] - others)
for i, w in enumerate(W_ALL):
    for k, v in w.items():
        if v > 0.001:
            groups[k].add([i], v, 'REPLACE')

mesh.parent = arm
md = mesh.modifiers.new("Armature", 'ARMATURE')
md.object = arm
arm.data.pose_position = 'POSE'
for p in mesh.data.polygons:
    p.use_smooth = True

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True,
                          export_animation_mode='ACTIONS', export_image_format='JPEG',
                          export_jpeg_quality=92, export_yup=True)
print("EXPORTED", OUT)
