# 印出每個高度切片的左右最寬、前後範圍（找手臂、脖子、肩膀）
import bpy, sys
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
o = next(o for o in bpy.data.objects if o.type == 'MESH')
pts = [o.matrix_world @ v.co for v in o.data.vertices]
zmin = min(p.z for p in pts); zmax = max(p.z for p in pts)
cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
print("cx", round(cx, 3), "zmin", round(zmin, 3), "zmax", round(zmax, 3))
N = 40
for k in range(N):
    z0 = zmin + (zmax - zmin) * k / N; z1 = z0 + (zmax - zmin) / N
    s = [p for p in pts if z0 <= p.z < z1]
    if not s:
        continue
    xs = [p.x - cx for p in s]; ys = [p.y for p in s]
    # 中央 |x|<0.15 的前後範圍（身體厚度）
    mid = [p.y for p in s if abs(p.x - cx) < 0.15]
    print("z=%+.3f frac=%.2f  x[%+.3f,%+.3f]  y[%+.3f,%+.3f]  midY[%s]" % (
        (z0 + z1) / 2, ((z0 + z1) / 2 - zmin) / (zmax - zmin), min(xs), max(xs), min(ys), max(ys),
        ("%+.3f,%+.3f" % (min(mid), max(mid))) if mid else "-"))
