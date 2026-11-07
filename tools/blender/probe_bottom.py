# 印出模型底部的高度圖（每格最低 z），找出腳的位置
import bpy, sys
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
o = next(o for o in bpy.data.objects if o.type == 'MESH')
pts = [o.matrix_world @ v.co for v in o.data.vertices]
zmin = min(p.z for p in pts)
N = 24
x0, x1, y0, y1 = -0.75, 0.75, -0.62, 0.62
grid = {}
for p in pts:
    if p.z > zmin + 0.35:
        continue
    i = int((p.x - x0) / (x1 - x0) * N); j = int((p.y - y0) / (y1 - y0) * N)
    k = (i, j)
    grid[k] = min(grid.get(k, 9), p.z)
print("zmin", round(zmin, 3))
print("rows = y from front(-) to back(+); cols = x from -0.75 to 0.75; value = (z - zmin)*100")
for j in range(N):
    row = []
    for i in range(N):
        v = grid.get((i, j))
        row.append("  ." if v is None else "%3d" % round((v - zmin) * 100))
    print("y=%+.2f " % (y0 + (j + 0.5) * (y1 - y0) / N) + "".join(row))
