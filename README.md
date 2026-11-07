# 派派森林程式樹屋（Godot 4.7）

3D 繪本風家具佈置遊戲。故事：派派鼠剛搬進派派森林的地洞樹屋，派派狼帶著派派兔來拜訪（第一次進遊戲會演開場）。在派派森林要用 print() 才能說話，所以前三個任務是「用程式碼對話」：print() 說話 → 變數與 f-string → input() 回答派派狼的問題。
平常用滑鼠擺家具、看派派鼠閒晃；接派派狼的任務時，才進入寫程式模式。學生用簡化版 Python 照「任務單」寫程式，派派鼠和家具會把程式演一遍，交件後由檢查器列出評估報告。

## 執行

```bash
"D:/Godot_v4/Godot_v4.7.2-stable_win64.exe" --path .
```

測試（直譯器 + 七份任務單 + 檢查器，共 78 項）：

```bash
"D:/Godot_v4/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

開發用自動截圖：`tools/shot.sh "task:T01_print;demo_bg;wait:5;png:C:/…/a.png"`（步驟見 `scripts/main.gd` 的 `_auto_shot`）。

## 操作

| 模式 | 操作 |
|---|---|
| 家 | 左鍵拿起／放下家具、R 旋轉、Delete 收回收藏冊、Esc 取消；點門口的派派狼或「派派狼的任務」接任務 |
| 視角 | 右鍵拖曳旋轉、滾輪縮放、中鍵拖曳或 WASD 平移、Q/E 轉 90 度 |
| 任務 | 程式跑到 input() 時，派派狼的問題會出現在氣泡和回答框，輸入回答按 Enter（交件時由測資的 `inputs` 自動回答）；▶ 看示範（演標準答案，不顯示程式）、▶ 執行（用你寫的值）、單步、暫停、速度、重來、★ 交件（含隱藏測資） |

## 架構

```
scripts/python/   py_lexer → py_parser → py_interp：簡化版 Python，中文錯誤訊息，整支先跑完並記錄 trace
scripts/task/     task_runner：trace → 依本題句型轉成動作 → 在 WorldModel 先算一遍
                  task_checker：嚴格列出所有偏差（findings），評分政策另外決定
                  playback：把 timeline 一步步演出（亮行、變數、輸出、動作）
scripts/world/    world_model（純邏輯格子）、room_view（3D 畫面）、models（佔位模型）、gopher_actor、camera_rig
scripts/ui/       task_panel（任務單＋程式碼＋輸出）、report_panel、home_hud、bubble_layer
data/tasks/*.json 任務單（每題一份）
data/furniture.json 家具定義；data/home.json 新玩家的家
```

存檔在 `user://save.json`（網頁版會存在瀏覽器）。

## 任務單格式（schema 1）

每題一份 `data/tasks/<id>.json`，主要欄位：

| 欄位 | 說明 |
|---|---|
| `title` `concept` `difficulty` `track` | 標題、教學目標、難度、`main` 主線／`side` 支線 |
| `npc_line` `sheet` | 派派兔的氣泡台詞；任務單內容（`story` `given` `rules` `expected`，可用 `[b]粗體[/b]`） |
| `print_role` | 這題 print 的意思：`action` 動作、`speech` 對派派兔說話、`mixed` 符合句型是動作，其他是說話、`dialogue` 對話任務 |
| `dialogue` | 對話任務的劇本，依序比對：`{"who": "wolf", "say": "{total}顆！"}` 是 NPC 台詞（`{變數}` 用標準答案的值填入）；`{"who": "wolf", "ask": true}` 對應學生的一個 `input()`；`{"who": "gopher"}` 對應學生的一個 `print()`。派派鼠要說的話＝標準答案用同一組測資跑出來的文字，一字不差才算聽懂 |
| `sheet.howto` | 對話任務在任務單上的「怎麼說話」表：`[["程式", "說明"], …]` |
| `patterns` | 句型表：`{"say": "向前推{n}格", "act": "push", "desc": "…"}`，`{n}` 是整數參數 |
| `room` | 房間大小、家具、派派鼠起點、`spots`（「走到〇〇」要站的格子與面向）、`npcs`（`[{"who": "wolf", "cell": [3, 3], "dir": "W"}]` 站在房間裡；沒寫就站在屋外西側） |
| `starter_code` `given_vars` | 預先寫好的程式、派派兔給的變數（隱藏測資會替換它的值） |
| `reference` `tests` | 標準答案；測資（`hidden: true` 為隱藏測資，`vars` 為替換值，`inputs` 為 input() 依序讀到的回答） |
| `goal_items` | 要比對最終位置的家具 |
| `rules` | 寫法規則：`given_var` `only_print` `must_use`（If/Else/JoinedStr…）`must_use_op` `var_in_print` `max_lines` `must_call`（`{"name": "input", "hint": "…"}`）`custom`（掛自訂 GDScript） |
| `scoring.overrides` | 調整嚴格度，例如 `{"output.whitespace": "warn", "rule.*": "info"}` |
| `builtins` `modules` | 這題可用的內建函式、可 import 的模組（之後 `gopher.walk(a)` 用） |
| `reward` | 獎勵家具與訊息 |

動作 `act`：`walk_to`（spot）、`forward`（n）、`turn_left`、`turn_right`、`pick_up`、`put_down`、`push`（n）、`say`。

評分預設：語法錯誤、執行錯誤、動作失敗、輸出不一致、位置不對、刪掉給定變數 → 不通過；其他寫法規則 → 過關但少一顆星。

## 尚未完成

- 正式 3D 模型：派派鼠、派派兔、派派狼由混元 3D（Hunyuan3D-2）生成，經 `tools/blender/rig_hy3d.py` 修正並上骨架（`models/gopher/gopher_rigged.glb`、`models/rabbit/rabbit_rigged.glb`、`models/wolf/wolf_rigged.glb`；用法 `blender -b -P rig_hy3d.py -- kenney.glb 原檔.glb 輸出.glb gopher|rabbit|wolf`）、小椅子（`models/chair.glb`，陽光小椅子用 `model_tint` 染黃）。其餘家具仍是程式拼的佔位模型；Thrixel 免費額度剩 13 方塊，雕塑次數 2026-12-01 重置。換模型：把 GLB 放進 `models/`，在 `furniture.json` 填 `model`（可選 `model_fill` `model_yaw` `model_tint`），會自動縮放貼地並加描邊。
- Kenney 模型（CC0，免費可商用，不需標註；授權檔在 `models/kenney/License-*.txt`）：Furniture Kit 的桌子、圓桌、書櫃、盆栽、沙發、邊桌、長椅、衣帽架、復古電視、收音機、書、小盆栽；Nature Kit 與 Fantasy Town Kit 的樹、花、灌木、蘑菇、石子路、柵欄、路燈、噴水池、攤位、推車（屋外小鎮景色，見 `room_view.gd` 的 `OUTDOOR`）。載入時會自動校正 Kenney 偏白的顏色並套繪本色票（`models.gd` 的 `KENNEY_PALETTE`）。
- 網頁版：需要安裝 Godot 網頁匯出範本，並放入 Noto Sans TC 字型到 `fonts/`（網頁沒有系統中文字型）。
- 管理員的任務設計器（第二版）。
