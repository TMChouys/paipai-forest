# 腳部特寫：從側面、後方低角度、斜後方渲染（檢查腳的形狀）
# 用法：blender -b --factory-startup --python tools/blender/feet_view.py -- <in.glb> <out_dir> [prefix]
import bpy, sys, os
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PREFIX = args[2] if len(args) > 2 else "feet"
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.data.pose_position = 'REST'
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 500; sc.render.resolution_y = 400
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.55, 0.6, 0.5)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.42
c = Vector((0, 0.0, 0.08))
views = {"side": Vector((1, 0, 0.1)), "back": Vector((0, 1, 0.25)), "q34back": Vector((0.7, 0.7, 0.3)),
         "front": Vector((0, -1, 0.2)), "q34front": Vector((0.7, -0.7, 0.25)), "bottom": Vector((0.0, -0.001, -1)),
         "lowside": Vector((1, 0.15, -0.12))}
for nm, d in views.items():
    cam.location = c + d.normalized() * 2
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(OUT, f"{PREFIX}_{nm}.png")
    bpy.ops.render.render(write_still=True)
print("DONE")
