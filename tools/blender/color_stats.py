# 比較兩張圖的主要色塊（毛、奶油色、背心綠）中位數顏色（sRGB 0-255）
import bpy, sys, colorsys
import numpy as np
args = sys.argv[sys.argv.index("--") + 1:]

def load_pixels(path):
    if path.endswith(".glb"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
        im = next(i for i in bpy.data.images if i.size[0] > 0)
    else:
        im = bpy.data.images.load(path)
    im.colorspace_settings.name = 'sRGB'
    a = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
    return a

def classes(a):
    a = a[a[:, 3] > 0.5][:, :3]
    a = a[::7]
    mx = a.max(1); mn = a.min(1)
    v = mx; s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    r, g, b = a[:, 0], a[:, 1], a[:, 2]
    # 色相（0..1）
    h = np.zeros(len(a))
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    out = {}
    out["fur"] = a[(h > 0.03) & (h < 0.12) & (s > 0.4) & (v > 0.35) & (v < 0.85)]
    out["cream"] = a[(h > 0.06) & (h < 0.16) & (s < 0.35) & (v > 0.8)]
    out["vest"] = a[(h > 0.13) & (h < 0.3) & (s > 0.3) & (v > 0.25) & (v < 0.8)]
    out["dark"] = a[(v < 0.3) & (s > 0.2)]
    return out

for path in args:
    c = classes(load_pixels(path))
    print("FILE", path.split("/")[-1].split("\\")[-1])
    for k, v in c.items():
        if len(v):
            m = np.median(v, axis=0)
            print("  %-6s n=%6d median rgb=(%3d,%3d,%3d)" % (k, len(v), *(m * 255).round()))
