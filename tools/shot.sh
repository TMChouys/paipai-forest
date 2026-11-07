#!/usr/bin/env bash
# 開發用：tools/shot.sh "wait:2;png:/abs/path.png"
G="/d/Godot_v4/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.."
timeout ${TIMEOUT:-90} "$G" --path . --resolution 1280x720 -- "--shot=$1" 2>&1 | grep -vE "^\s*$|Godot Engine|OpenGL API|^\s+at:|GDScript backtrace|^\s+\[[0-9]+\]" | head -40
