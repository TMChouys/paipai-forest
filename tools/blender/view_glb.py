# 檢視任意 GLB：印出資訊並從多個角度（含底部）渲染貼圖預覽。
# 用法：blender -b --factory-startup --python tools/blender/view_glb.py -- <in.glb> <out_dir> [prefix]
import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREFIX = args[2] if len(args) > 2 else "view"
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
for o in meshes:
    print("MESH", o.name, "verts", len(o.data.vertices), "faces", len(o.data.polygons), "mats", [m.name for m in o.data.materials], "uv", [u.name for u in o.data.uv_layers])
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
print("BOUNDS", tuple(round(c, 3) for c in mn), tuple(round(c, 3) for c in mx))
for im in bpy.data.images:
    print("IMAGE", im.name, tuple(im.size))
c = (mn + mx) / 2
size = max(mx - mn)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 600; sc.render.resolution_y = 600
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.5, 0.5, 0.5)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = size * 1.15
views = {"front": Vector((0, -1, 0)), "back": Vector((0, 1, 0)), "left": Vector((1, 0, 0)), "right": Vector((-1, 0, 0)),
         "q34": Vector((0.7, -0.7, 0.25)), "bottom": Vector((0, -0.001, -1))}
for nm, d in views.items():
    cam.location = c + d.normalized() * size * 3
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(OUT, f"{PREFIX}_{nm}.png")
    bpy.ops.render.render(write_still=True)
print("DONE")
