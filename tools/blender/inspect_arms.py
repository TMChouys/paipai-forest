import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=sys.argv[-1])
for o in bpy.data.objects:
    if o.type == 'MESH':
        for gname in ('arm-left', 'leg-left'):
            g = o.vertex_groups.get(gname)
            if not g: continue
            pts = [o.matrix_world @ v.co for v in o.data.vertices if any(e.group == g.index and e.weight > 0.5 for e in v.groups)]
            if pts:
                print("GROUP", o.name, gname, [round(min(p[i] for p in pts), 3) for i in range(3)], [round(max(p[i] for p in pts), 3) for i in range(3)])
for a in bpy.data.actions[:40]:
    chans = set()
    for fc in getattr(a, 'fcurves', []) or []:
        chans.add(fc.data_path)
    if not chans:
        try:
            for l in a.layers:
                for st in l.strips:
                    for cb in st.channelbags:
                        for fc in cb.fcurves: chans.add(fc.data_path)
        except Exception as e: print("ERR", e)
    arm = sorted(c for c in chans if 'arm-left' in c)
    print("ACT", a.name, arm)
