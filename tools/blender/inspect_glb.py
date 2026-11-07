# 用法：blender -b --factory-startup --python tools/blender/inspect_glb.py -- model.glb
import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=sys.argv[-1])
for o in bpy.data.objects:
    print("OBJ", o.name, o.type, tuple(round(v, 3) for v in o.location), tuple(round(v, 3) for v in o.dimensions), o.parent.name if o.parent else None)
    if o.type == 'ARMATURE':
        for b in o.data.bones:
            print("  BONE", b.name, b.parent.name if b.parent else None, tuple(round(v, 3) for v in b.head_local), tuple(round(v, 3) for v in b.tail_local))
    if o.type == 'MESH':
        print("  verts", len(o.data.vertices), "groups", [g.name for g in o.vertex_groups], "mats", [m.name for m in o.data.materials])
print("ACTIONS", [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])
