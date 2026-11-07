# 找出頭部兩側貼圖上的深色記號在 3D 的位置（座標已換成 rig_hy3d.py 的正規化座標）
import bpy, sys
import numpy as np
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0], merge_vertices=True, import_shading="SMOOTH")
o = next(o for o in bpy.data.objects if o.type == 'MESH')
me = o.data
co = np.array([(o.matrix_world @ v.co)[:] for v in me.vertices])
cx = (co[:, 0].min() + co[:, 0].max()) / 2; zmin, zmax = co[:, 2].min(), co[:, 2].max()
HT = float(args[1]) if len(args) > 1 else 0.74
LUM = float(args[2]) if len(args) > 2 else 0.22
Z0, Z1 = (float(args[3]), float(args[4])) if len(args) > 4 else (0.33, 0.72)
s = HT / (zmax - zmin)
co[:, 0] -= cx; co[:, 2] -= zmin; co *= s
img = next(i for i in bpy.data.images if i.size[0] > 0)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
uvl = me.uv_layers.active.data
hits = []
for poly in me.polygons:
    for li, vi in zip(poly.loop_indices, poly.vertices):
        p = co[vi]
        if abs(p[0]) < 0.08 or not (Z0 < p[2] < Z1):
            continue
        u, v = uvl[li].uv
        c = px[min(H - 1, int(v * H)), min(W - 1, int(u * W)), :3]
        lum = c.mean()
        if lum < LUM:
            hits.append((p[0], p[1], p[2], lum))
hits = np.array(hits)
print("N dark", len(hits))
for side in (1, -1):
    h = hits[hits[:, 0] * side > 0]
    if len(h):
        print("side", side, "x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]" % (h[:, 0].min(), h[:, 0].max(), h[:, 1].min(), h[:, 1].max(), h[:, 2].min(), h[:, 2].max()))
for side in (1, -1):
    h = hits[(hits[:, 0] * side > 0.1)]
    print("side", side, "grid z rows (top->bottom) x y cols from -0.16 to 0.18 step 0.02")
    for zc in np.arange(Z1, Z0, -0.02):
        row = ""
        for yc in np.arange(-0.24, 0.26, 0.02):
            n = ((h[:, 2] >= zc - 0.01) & (h[:, 2] < zc + 0.01) & (h[:, 1] >= yc - 0.01) & (h[:, 1] < yc + 0.01)).sum()
            row += "%3d" % n if n else "  ."
        print("z=%.2f %s" % (zc, row))
