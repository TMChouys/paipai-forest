# 取模型表面某些點附近的貼圖顏色（sRGB 0-255），用來和參考圖比色
# 用法：blender -b --factory-startup --python sample_tex.py -- <glb> <總高H> name:x,y,z ...
import bpy, sys
import numpy as np
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
o = next(o for o in bpy.data.objects if o.type == 'MESH')
me = o.data
co = np.array([(o.matrix_world @ v.co)[:] for v in me.vertices])
cx = (co[:, 0].min() + co[:, 0].max()) / 2; zmin, zmax = co[:, 2].min(), co[:, 2].max()
co[:, 0] -= cx; co[:, 2] -= zmin; co *= float(args[1]) / (zmax - zmin)
img = next(i for i in bpy.data.images if i.size[0] > 0)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
uv = np.zeros((len(me.vertices), 2))
for l in me.loops:
    uv[l.vertex_index] = me.uv_layers.active.data[l.index].uv
for spec in args[2:]:
    name, xyz = spec.split(":")
    p = np.array([float(t) for t in xyz.split(",")])
    d = np.linalg.norm(co - p, axis=1)
    idx = np.where(d < 0.025)[0]
    if len(idx) == 0:
        idx = [int(d.argmin())]
    c = [px[min(H - 1, int(uv[i, 1] * H)), min(W - 1, int(uv[i, 0] * W)), :3] for i in idx]
    print("SAMPLE %-10s n=%4d rgb=%s" % (name, len(idx), (np.median(c, 0) * 255).round()))
