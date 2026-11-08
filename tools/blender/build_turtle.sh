#!/usr/bin/env bash
# 慢慢館長：修模型（fix_turtle.py）→ 上骨架（rig_hy3d.py turtle）→ models/turtle/turtle_rigged.glb
# 用法：tools/blender/build_turtle.sh [預覽資料夾]
set -e
cd "$(dirname "$0")/../.."
B="${BLENDER:-D:/Blender 5.2/blender.exe}"
TMP="${TMPDIR:-/tmp}/turtle_build"; mkdir -p "$TMP"
"$B" -b --factory-startup --python tools/blender/fix_turtle.py -- models/turtle/turtle_1.glb "$TMP/turtle_fixed.glb" ${1:+"$1"} | grep -E "SKIN|OLD|ROBE|EXPORTED|Error"
"$B" -b --factory-startup --python tools/blender/rig_hy3d.py -- "$(pwd)/models/kenney/mini/character-male-a.glb" "$TMP/turtle_fixed.glb" "$(pwd)/models/turtle/turtle_rigged.glb" turtle | grep -E "PINNED|WALK|EXPORTED|Error"
