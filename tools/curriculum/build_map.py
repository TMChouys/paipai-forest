"""產生 data/curriculum/knowledge_map.json（派森小鎮任務書的知識地圖）。

第一版由這個腳本產生；之後請用管理者儀表板（tools/dashboard/index.html）
或 curriculum-planner Agent 直接改 JSON，不要再重跑這個腳本覆蓋掉修改。
用法：python -I tools/curriculum/build_map.py [--force]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "curriculum", "knowledge_map.json")

AREAS = [
    ("A", "程式起步", "print、註解：讓派派鼠開口說話", "零基礎入門班 ch1–ch2；運算思維 Ch1–2", "#ffcf6b"),
    ("B", "變數與資料型態", "把東西存起來、數字和文字不一樣", "零基礎入門班 ch2；運算思維 Ch2", "#f4a261"),
    ("C", "運算子", "計算、比較、且／或／不是", "零基礎入門班 ch2；運算思維 Ch3", "#e9c46a"),
    ("D", "字串與輸入輸出", "input、f-string、字串的小工具", "零基礎入門班 ch3、ch7；運算思維 Ch2", "#9fd18f"),
    ("E", "選擇結構", "if／else：依情況做不同的事", "零基礎入門班 ch4；運算思維 Ch4", "#8fc1e3"),
    ("F", "迴圈", "for、while：重複做事", "零基礎入門班 ch5；運算思維 Ch5", "#b8a1e3"),
    ("G", "串列與元組", "一次存很多東西", "零基礎入門班 ch6；運算思維 Ch6", "#f2a7b8"),
    ("H", "字典與集合", "用名字找東西、不重複的收藏", "零基礎入門班 ch8；運算思維 Ch6", "#d4b483"),
    ("I", "函式與模組", "把做法包起來重複使用", "零基礎入門班 ch7；運算思維 Ch7", "#9ad0c2"),
    ("J", "檔案與例外", "把日記存起來、出錯也不慌", "零基礎入門班 ch9；運算思維 Ch8", "#c9b79c"),
    ("K", "演算法應用", "搜尋、排序：把學過的組合起來", "零基礎入門班 ch8 延伸", "#e07a5f"),
]

# 引擎目前支援：print、input、變數、四則、比較、邏輯、f-string、if、for/while、break/continue、
# 字串方法 upper/lower/strip/replace/split、串列字面值／索引／走訪、len/min/max/abs/round/range。
# needs 列出要先擴充直譯器才能做成可玩任務的功能。
CONCEPTS = [
    # id, area, name, summary, prereqs, textbook, needs
    ("print", "A", "print() 說一句話", "用 print(\"…\") 讓派派鼠把字說出來。", [], "入門班 1.5 / 運算思維 2", []),
    ("comment", "A", "註解 #", "# 後面是寫給人看的筆記，電腦不會執行。", ["print"], "入門班 2.1", []),
    ("print_multi", "A", "print 一次說好幾個", "print(a, b) 用逗號隔開，一次印出好幾個值。", ["print"], "入門班 3.3", []),
    ("variable", "B", "變數", "name = \"派派鼠\"：把值存進有名字的盒子。", ["print"], "入門班 2.3", []),
    ("bool", "B", "布林值 True / False", "只有「對」和「不對」兩種值。", ["variable"], "入門班 2.3.5", []),
    ("types", "B", "數字和文字不一樣", "3 + 4 是 7，\"3\" + \"4\" 是 \"34\"：整數、小數、字串是不同型態。", ["variable", "arith"], "入門班 2.3.3", []),
    ("convert", "B", "型態轉換 int() / str()", "把文字變數字、數字變文字。", ["types"], "入門班 2.3.6", []),
    ("reassign", "B", "更新變數", "carrots = carrots + 1：用舊的值算出新的值。", ["variable", "arith"], "入門班 2.3", []),
    ("arith", "C", "四則運算 + - * /", "讓電腦幫你算加減乘除。", ["print"], "入門班 2.4", []),
    ("floordiv_mod", "C", "整數除法 // 與餘數 %", "平分東西：每人幾個、剩下幾個。", ["arith", "variable"], "入門班 2.4", []),
    ("aug_assign", "C", "複合指定 +=", "fish += 1 是 fish = fish + 1 的簡寫。", ["reassign"], "入門班 2.4", []),
    ("compare", "C", "比較運算子", "> < == != 比大小，結果是 True / False。", ["arith", "bool"], "入門班 2.4", []),
    ("logic", "C", "邏輯運算 and / or / not", "「而且」「或是」「不是」把條件接起來。", ["compare"], "入門班 2.4", []),
    ("str_concat", "D", "字串相加 +", "\"親愛的\" + name：把文字接在一起。", ["variable"], "入門班 3.2", []),
    ("str_repeat", "D", "字串乘法 *", "\"喀嚓\" * 3：把文字重複好幾次。", ["str_concat", "arith"], "入門班 3.2", []),
    ("input", "D", "input() 問問題", "input(\"問題\") 會等玩家回答，回答一定是文字。", ["print", "variable"], "入門班 3.2.5", []),
    ("input_number", "D", "把回答變成數字", "int(input()) 讓回答可以拿來算。", ["input", "convert"], "入門班 3.2.5", []),
    ("fstring", "D", "f-string", "f\"{name}好\"：把變數的值放進句子裡。", ["variable"], "入門班 3.3", []),
    ("len", "D", "len() 數長度", "len(\"派派鼠\") 是 3：數一數有幾個字。", ["variable"], "入門班 3.2", []),
    ("str_index", "D", "字串索引 s[0]", "從 0 開始數，拿出第幾個字。", ["variable"], "入門班 3.2", []),
    ("str_in", "D", "in：裡面有沒有", "\"寶庫\" in letter：信裡有沒有提到寶庫。", ["str_concat", "bool"], "入門班 3.2", []),
    ("str_methods", "D", "字串方法", "upper()、replace()、strip()：幫文字整理儀容。", ["variable"], "入門班 7.3", []),
    ("if", "E", "if：如果…就…", "條件成立才做。", ["compare"], "入門班 4.4", []),
    ("if_else", "E", "if / else", "成立做這個，不成立做那個。", ["if"], "入門班 4.4", []),
    ("elif", "E", "elif 多種情況", "很多種情況，依序檢查。", ["if_else"], "入門班 4.4", []),
    ("nested_if", "E", "巢狀 if", "if 裡面還有 if：先檢查大門，再檢查小門。", ["if_else"], "入門班 4.4", []),
    ("for_range", "F", "for 與 range(n)", "重複 n 次。", ["variable"], "入門班 5.1", []),
    ("range_args", "F", "range(起, 止, 間隔)", "從幾數到幾、一次跳幾格。", ["for_range"], "入門班 5.1.2", []),
    ("for_str", "F", "逐字走訪字串", "for ch in word：一個字一個字拿出來。", ["for_range", "str_index"], "入門班 5.1", []),
    ("accumulate", "F", "累加", "迴圈裡一直加：算出總數。", ["for_range", "aug_assign"], "入門班 5.1", []),
    ("while", "F", "while 迴圈", "條件成立就一直做，直到不成立。", ["compare", "aug_assign"], "入門班 5.2", []),
    ("break", "F", "break 提早離開", "找到了就停。", ["while", "if"], "入門班 5.3", []),
    ("continue", "F", "continue 跳過這次", "這個不要，換下一個。", ["for_range", "if"], "入門班 5.3", []),
    ("nested_loop", "F", "巢狀迴圈", "迴圈裡還有迴圈：一排一排、一棵一棵。", ["for_range"], "入門班 5.4", []),
    ("list", "G", "建立串列", "[\"蘑菇燈\", \"小花盆\"]：一個變數存很多東西。", ["variable"], "入門班 6.1", []),
    ("list_index", "G", "串列索引", "photos[0]：拿出第幾個。", ["list"], "入門班 6.2", []),
    ("for_list", "G", "走訪串列", "for p in photos：每一個都看一遍。", ["list", "for_range"], "入門班 6.3", []),
    ("list_in", "G", "in：在不在串列裡", "\"小花盆\" in items。", ["list", "str_in"], "入門班 6.3", []),
    ("split", "G", "split() 切成串列", "把一句話切成很多個詞。", ["list", "str_methods"], "入門班 7.3", []),
    ("list_append", "G", "append() 加進去", "收藏冊多了一件家具。", ["list"], "入門班 6.3", ["list_methods"]),
    ("list_remove", "G", "remove() / pop() 拿出來", "把東西從串列拿掉。", ["list_append"], "入門班 6.3", ["list_methods"]),
    ("list_sort", "G", "排序 sort() / sorted()", "由小到大排好。", ["list"], "入門班 6.3", ["list_methods"]),
    ("list_slice", "G", "切片 [a:b]", "拿出一段。", ["list_index"], "入門班 6.2", ["slice"]),
    ("tuple", "G", "元組", "不能改的串列。", ["list"], "入門班 8.1", ["tuple"]),
    ("dict", "H", "字典", "{\"蘑菇燈\": 3}：用名字找值。", ["list_index"], "入門班 8.3", ["dict"]),
    ("dict_update", "H", "字典新增與修改", "d[key] = value。", ["dict"], "入門班 8.3", ["dict"]),
    ("dict_get", "H", "get() 與 in 查字典", "查不到也不會出錯。", ["dict"], "入門班 8.3", ["dict"]),
    ("dict_loop", "H", "走訪字典 items()", "每一組名字和值都看一遍。", ["dict", "for_list"], "入門班 8.3", ["dict"]),
    ("set", "H", "集合", "不重複的收藏。", ["list"], "入門班 8.2", ["set"]),
    ("builtin", "I", "內建函式 max / min / abs / round", "電腦內建的小工具。", ["arith"], "入門班 7.1", []),
    ("def", "I", "定義函式 def", "把一串動作取個名字。", ["print"], "入門班 7.2", ["def"]),
    ("param", "I", "參數", "呼叫時把東西交給函式。", ["def", "variable"], "入門班 7.2", ["def"]),
    ("return", "I", "回傳值 return", "函式算完把答案交回來。", ["param"], "入門班 7.2", ["def"]),
    ("scope", "I", "區域變數與全域變數", "函式裡的變數只在裡面有效。", ["return"], "入門班 7.2", ["def"]),
    ("random", "I", "random 模組", "擲骰子、抽籤。", ["variable"], "入門班 7.1", ["module_random"]),
    ("time_mod", "I", "time / datetime 模組", "現在幾點、等一下。", ["variable"], "入門班 7.1", ["module_time"]),
    ("file_write", "J", "寫入檔案", "把日記寫進檔案。", ["str_concat"], "入門班 9.1", ["file"]),
    ("file_read", "J", "讀取檔案", "把信從檔案讀出來。", ["file_write", "for_list"], "入門班 9.1", ["file"]),
    ("try", "J", "try / except", "出錯也不慌，好好處理。", ["input_number"], "入門班 9.2", ["try"]),
]

# 每個概念一個「單一概念」任務（極簡版）。place / npc 用故事聖經裡已經有的地點與角色。
# id, concept, title, place, npc, difficulty, story, goal, expected, game_task
SINGLE = [
    ("print", "嘿！新來的", "treehouse", "wolf", 1, "派派狼第一次來拜訪，派派鼠要用 print() 打招呼。", "用 print() 依序說出註解寫的三句話。", "你好！我是派派鼠。", "D01_hello"),
    ("print", "小椅子想曬太陽", "treehouse", "rabbit", 2, "派派兔請派派鼠用句型表裡的 print() 指令，一步一步把椅子搬到窗邊。", "照句型表，用好幾個 print() 下指令。", "（椅子到窗邊）", "T01_print"),
    ("comment", "派派兔的讀書筆記", "treehouse", "rabbit", 1, "派派兔說：讀書時要在旁邊寫筆記，但筆記不用念出來。", "在程式裡寫一行 # 筆記，再用 print() 說一句「我寫好筆記了！」。", "我寫好筆記了！", None),
    ("print_multi", "拍拍鳥的合照名單", "front_yard", "crow", 1, "拍拍鳥要拍合照，請派派鼠一次報出三個名字。", "用一個 print()、逗號隔開，說出 派派鼠 派派狼 派派兔。", "派派鼠 派派狼 派派兔", None),
    ("variable", "信箱的名牌", "front_yard", "crow", 1, "拍拍鳥送信時找不到名牌，派派鼠把名字存進變數 name 再念出來。", "name = \"派派鼠\"，然後 print(name)。", "派派鼠", None),
    ("bool", "門鎖好了嗎？", "treehouse", "wolf", 1, "出門冒險前，派派狼要確認門鎖。", "door_locked = True，print(door_locked)。", "True", None),
    ("types", "派派兔的奇怪秤", "lavender", "rabbit", 2, "派派兔把兩包薰衣草的重量寫成文字，結果秤出 34 克？", "比較 print(3 + 4) 和 print(\"3\" + \"4\")，說出兩個結果。", "7 / 34", None),
    ("convert", "照片的編號", "front_yard", "crow", 2, "拍拍鳥的照片編號是數字，要接在文字後面得先轉成文字。", "n = 5；print(\"第\" + str(n) + \"張照片\")。", "第5張照片", None),
    ("reassign", "胡蘿蔔又長一根", "front_yard", "rabbit", 2, "胡蘿蔔園每天多長一根，派派兔請派派鼠更新數量。", "carrots = 3，再寫 carrots = carrots + 1，說出新的數量。", "4", None),
    ("arith", "一共幾顆橡果？", "treehouse", "wolf", 1, "派派狼帶了 3 顆，派派兔帶了 4 顆，一共幾顆？", "print(3 + 4)：讓電腦算。", "7", None),
    ("floordiv_mod", "平分橡果", "treehouse", "wolf", 2, "17 顆橡果分給 3 個人，每人幾顆？剩幾顆？", "用 // 算每人幾顆、% 算剩幾顆。", "5 / 2", None),
    ("aug_assign", "溪畔釣魚計數", "creek", "wolf", 2, "派派狼每釣到一條魚就喊一聲，派派鼠用 += 記數。", "fish = 0，寫兩次 fish += 1，說出 fish。", "2", None),
    ("compare", "誰的胡蘿蔔比較長？", "front_yard", "rabbit", 1, "派派兔的胡蘿蔔 12 公分，派派鼠的 9 公分。", "print(12 > 9)。", "True", None),
    ("logic", "可以出發去螢光寶庫嗎？", "vault", "wolf", 2, "派派狼說：要有燈「而且」有水才可以出發。", "has_lamp 和 has_water 都設好，print(has_lamp and has_water)。", "True", None),
    ("str_concat", "信的開頭", "front_yard", "rabbit", 1, "派派兔教派派鼠寫回信，開頭要寫「親愛的」加上名字。", "name = \"派派狼\"，print(\"親愛的\" + name)。", "親愛的派派狼", None),
    ("str_repeat", "喀嚓喀嚓喀嚓", "sky_top", "crow", 1, "拍拍鳥的木頭相機連拍三張。", "print(\"喀嚓\" * 3)。", "喀嚓喀嚓喀嚓", None),
    ("input", "你叫什麼名字？", "treehouse", "rabbit", 1, "派派兔問新鄰居的名字，派派鼠把回答念出來。", "name = input(\"你叫什麼名字？\")，再 print(name)。", "（玩家輸入的名字）", None),
    ("input_number", "要幾顆橡果？", "treehouse", "wolf", 2, "派派狼問要幾顆橡果，回答要變成數字才能多給一顆。", "n = int(input())，print(n + 1)。", "（輸入 3 → 4）", None),
    ("fstring", "照片背面的說明", "sky_top", "crow", 1, "拍拍鳥在照片背面寫上誰在哪裡。", "name、place 兩個變數，print(f\"{name}在{place}\")。", "派派鼠在天空樹頂", None),
    ("len", "信寫了幾個字？", "front_yard", "rabbit", 1, "派派兔想知道回信有多長。", "print(len(letter))。", "（字數）", None),
    ("str_index", "地下城密碼的第一個字", "dungeon", "wolf", 2, "地下城門口寫著密碼，第一個字就是開門口令。", "code = \"螢光寶庫\"，print(code[0])。", "螢", None),
    ("str_in", "信裡有提到寶庫嗎？", "front_yard", "crow", 2, "拍拍鳥送來一封信，派派狼只想知道有沒有提到「寶庫」。", "print(\"寶庫\" in letter)。", "True", None),
    ("str_methods", "幫忙改錯字", "treehouse", "rabbit", 2, "派派兔的筆記把「蘿蔔」寫成「羅蔔」。", "用 replace() 改好再 print。", "胡蘿蔔要澆水", None),
    ("if", "下雨要帶傘", "treehouse", "rabbit", 1, "如果在下雨，派派鼠就要說「帶傘！」。", "rain = True；if rain: print(\"帶傘！\")。", "帶傘！", None),
    ("if_else", "下雨還是晴天？", "treehouse", "rabbit", 2, "下雨就拿傘，晴天就搬椅子曬太陽。", "if / else 兩種情況各說一句。", "（依天氣不同）", "T03_if_rain"),
    ("elif", "薰衣草開了幾成？", "lavender", "rabbit", 2, "派派兔依花開的數量說「還沒開／開一半／全開了」。", "if / elif / else 三種情況。", "開一半", None),
    ("nested_if", "地下城的兩道門", "dungeon", "wolf", 3, "先檢查有沒有燈，有燈再檢查有沒有鑰匙。", "if 裡面再寫一個 if。", "可以進去了！", None),
    ("for_range", "喊三次「到！」", "forest_path", "wolf", 1, "派派狼點名，派派鼠要喊三次。", "for i in range(3): print(\"到！\")。", "到！×3", None),
    ("range_args", "天空樹頂的階梯", "sky_top", "crow", 2, "拍拍鳥一次跳兩階，數 2、4、6、8、10。", "range(2, 11, 2)。", "2 4 6 8 10", None),
    ("for_str", "一個字一個字念信", "front_yard", "crow", 2, "拍拍鳥念信很慢，一次念一個字。", "for ch in word: print(ch)。", "派／派／鼠", None),
    ("accumulate", "一週撿了幾顆橡果", "forest_path", "wolf", 2, "一週七天每天撿 3 顆，用迴圈加起來。", "total = 0；迴圈裡 total += 3。", "21", None),
    ("while", "數螢火蟲", "vault", "wolf", 2, "螢光寶庫裡，一直數到 5 隻螢火蟲就停。", "while count < 5: count += 1。", "1 2 3 4 5", None),
    ("break", "釣到就收竿", "creek", "wolf", 2, "一直甩竿，釣到魚就停。", "while True 裡用 break。", "釣到了！", None),
    ("continue", "跳過枯掉的花", "lavender", "rabbit", 2, "派派兔澆花，枯掉的那盆跳過。", "for 裡用 if + continue。", "（只說沒枯的花）", None),
    ("nested_loop", "胡蘿蔔園的格子", "front_yard", "rabbit", 3, "胡蘿蔔園有 2 排、每排 3 棵。", "for 裡面再一個 for，說出每一棵的位置。", "1-1 1-2 1-3 2-1 …", None),
    ("list", "相簿裡的照片", "treehouse", "crow", 1, "拍拍鳥把照片地點列成一張清單。", "photos = [\"森林\", \"薰衣草原\", \"寶庫\"]，print(photos)。", "['森林', '薰衣草原', '寶庫']", None),
    ("list_index", "第一張是哪裡？", "treehouse", "crow", 1, "相簿第一頁是哪一張照片？", "print(photos[0])。", "森林", None),
    ("for_list", "派派兔點名澆花", "front_yard", "rabbit", 2, "花圃清單裡的每一盆都要澆水。", "for f in flowers: print(f\"幫{f}澆水\")。", "幫薰衣草澆水 …", None),
    ("list_in", "收藏冊裡有沒有？", "treehouse", "rabbit", 1, "派派兔想知道收藏冊裡有沒有「小花盆」。", "print(\"小花盆\" in items)。", "True", None),
    ("split", "購物清單", "front_yard", "crow", 2, "拍拍鳥送來的清單用空白隔開，切成串列。", "words = note.split()，print(words)。", "['麵包', '牛奶', '胡蘿蔔']", None),
    ("list_append", "收藏冊多一件", "treehouse", "rabbit", 1, "完成任務拿到新家具，放進收藏冊。", "items.append(\"蘑菇檯燈\")。", "[… '蘑菇檯燈']", None),
    ("list_remove", "把家具拿出來擺", "treehouse", "rabbit", 2, "從收藏冊拿出一件擺到地上。", "items.remove(\"小花盆\")。", "（少了小花盆）", None),
    ("list_sort", "照片依日期排好", "treehouse", "crow", 2, "拍拍鳥的照片日期亂掉了。", "dates.sort()。", "[1, 3, 8]", None),
    ("list_slice", "前三張照片", "treehouse", "crow", 2, "只看相簿的前三張。", "photos[0:3]。", "（前三張）", None),
    ("tuple", "不能改的座標", "sky_top", "crow", 2, "天空樹頂的位置是固定的。", "spot = (3, 5)。", "(3, 5)", None),
    ("dict", "家具的名牌", "treehouse", "rabbit", 2, "每件家具都有名字和數量。", "stock = {\"小花盆\": 2}，print(stock[\"小花盆\"])。", "2", None),
    ("dict_update", "又多一個小花盆", "treehouse", "rabbit", 2, "收到新的小花盆，數量加一。", "stock[\"小花盆\"] += 1。", "3", None),
    ("dict_get", "查不到也沒關係", "treehouse", "rabbit", 2, "查一件還沒有的家具，不要讓程式出錯。", "stock.get(\"沙發\", 0)。", "0", None),
    ("dict_loop", "整理收藏冊", "treehouse", "rabbit", 3, "把每件家具和數量都念一遍。", "for k, v in stock.items()。", "小花盆 3 …", None),
    ("set", "不重複的足跡", "forest_path", "wolf", 2, "派派狼記下今天去過的地方，同一個地方只記一次。", "places = set()；add()。", "{'溪畔', '寶庫'}", None),
    ("builtin", "誰撿得最多？", "forest_path", "wolf", 1, "比一比三個人撿的橡果。", "print(max(5, 8, 3))。", "8", None),
    ("def", "派派鼠的招牌招呼", "treehouse", "wolf", 2, "派派狼說：每次見面都說一樣的話，乾脆包成一個招式。", "def greet(): print(\"嗨！\")，然後呼叫兩次。", "嗨！×2", None),
    ("param", "對誰打招呼？", "treehouse", "rabbit", 2, "招呼要能換人。", "def greet(name)。", "嗨，派派兔！", None),
    ("return", "幫忙算橡果", "treehouse", "wolf", 3, "函式算好總數交回來，再由派派鼠說出來。", "def total(a, b): return a + b。", "7", None),
    ("scope", "函式裡的秘密", "dungeon", "wolf", 3, "函式裡的變數，出了函式就看不到。", "比較函式內外的同名變數。", "（兩個不同的值）", None),
    ("random", "拍拍鳥的抽籤", "sky_top", "crow", 2, "拍拍鳥抽籤決定下週去哪裡拍照。", "random.choice(places)。", "（隨機地點）", None),
    ("time_mod", "現在幾點了？", "treehouse", "rabbit", 2, "派派兔看時鐘決定要不要泡茶。", "time.localtime()。", "（現在時間）", None),
    ("file_write", "寫日記", "treehouse", "rabbit", 2, "把今天的冒險寫進日記本。", "open(\"diary.txt\", \"w\").write(…)。", "（日記檔）", None),
    ("file_read", "讀回信", "front_yard", "crow", 3, "把信件檔案一行一行讀出來。", "for line in open(\"letter.txt\")。", "（信的每一行）", None),
    ("try", "打錯也不怕", "treehouse", "wolf", 3, "派派狼問數字，派派鼠卻回答「很多」。", "try: int(input()) except: …", "請輸入數字喔！", None),
]

# 複合知識任務：一定標示 compound，難度 ≥ 3
COMPOUND = [
    # id, title, concepts, place, npc, difficulty, story, goal, expected, game_task
    ("X_acorns", "帶了幾顆橡果？", ["variable", "arith", "floordiv_mod", "fstring"], "treehouse", "wolf", 3,
     "派派狼問派派鼠搬家帶了幾袋橡果、一共幾顆、能不能分一半。", "用變數、計算和 f-string 回答三個問題。", "我帶了3袋，每袋12顆！…", "D02_acorns"),
    ("X_questions", "派派狼的問題", ["input", "input_number", "fstring"], "treehouse", "wolf", 3,
     "派派狼考新來的：最喜歡吃什麼？一天吃幾顆橡果？", "用 input() 讓派派狼問，再用 f-string 回答。", "我最喜歡吃…！", "D03_questions"),
    ("X_long_table", "長桌要往前挪", ["variable", "fstring"], "treehouse", "rabbit", 3,
     "派派兔請派派鼠把長桌往前推幾格，再回報推了幾格。", "用變數決定格數，用 f-string 回報。", "學姊，長桌往前推了2格", "T02_variable"),
    ("X_crate", "木箱有多重？", ["compare", "if_else"], "treehouse", "rabbit", 3,
     "木箱太重就請派派狼幫忙，不重就自己搬（剛好等於上限時要特別注意）。", "比較運算子＋if / else，注意邊界值。", "（依重量不同）", "S01_crate_weight"),
    ("X_guess", "猜猜我是誰", ["input", "if_else"], "lavender", "rabbit", 3,
     "派派兔躲在薰衣草叢後面，派派鼠猜名字，猜對了她才出來。", "input() 讀答案，if / else 判斷對不對。", "答對了！", None),
    ("X_ripe", "挑出成熟的胡蘿蔔", ["for_list", "if"], "front_yard", "rabbit", 3,
     "胡蘿蔔長度清單裡，超過 10 公分的才拔。", "for 走訪串列＋if 篩選。", "拔起 12 公分的胡蘿蔔 …", None),
    ("X_door", "地下城的密碼門", ["while", "input", "compare"], "dungeon", "wolf", 4,
     "老樹根下的地下城入口，答對密碼門才會開，答錯可以一直再試。", "while 迴圈反覆 input()，直到答對。", "門開了！", None),
    ("X_total", "一週的橡果帳本", ["accumulate", "for_list", "fstring"], "forest_path", "wolf", 3,
     "派派狼記下一週每天撿的橡果，算出總數再報告。", "迴圈累加串列，再用 f-string 說出總數。", "這週一共撿了…顆！", None),
    ("X_photo_machine", "拍拍鳥的照片編號機", ["param", "for_range", "fstring"], "sky_top", "crow", 4,
     "拍拍鳥想要一台機器，自動幫照片編號。", "寫一個有參數的函式，用迴圈呼叫它。", "第1張：天空樹頂 …", None),
    ("X_mail_count", "郵件分類", ["dict_loop", "accumulate"], "front_yard", "crow", 4,
     "拍拍鳥要統計每個人收到幾封信。", "字典記數量，走訪字典算總數。", "派派狼：2 封 …", None),
    ("X_diary", "不怕打錯的日記本", ["file_write", "try", "input"], "treehouse", "rabbit", 4,
     "派派兔的日記本要記下今天收成幾根胡蘿蔔，打錯也不會壞掉。", "try 處理輸入錯誤，再寫進檔案。", "日記寫好了！", None),
    ("K_max", "最大顆的橡果", ["for_list", "if", "variable"], "forest_path", "wolf", 3,
     "派派狼要從一袋橡果裡找出最大顆的（不能用 max）。", "用迴圈和 if 自己找最大值。", "最大的是 9 公克", None),
    ("K_search", "找出寶庫裡的那本書", ["for_list", "if", "break"], "vault", "wolf", 4,
     "螢光寶庫的書架上一本一本找，找到就停。", "循序搜尋：走訪＋比對＋break。", "在第 4 格找到了！", None),
    ("K_binary", "猜數字：寶箱密碼", ["while", "if_else", "floordiv_mod", "input_number"], "vault", "wolf", 5,
     "寶箱密碼是 1 到 100，每猜一次寶箱會說太大或太小，用最少次猜中。", "二分搜尋。", "第 7 次猜中！", None),
    ("K_bubble", "照片依日期排好（自己排）", ["nested_loop", "list_index", "compare"], "treehouse", "crow", 5,
     "拍拍鳥的照片亂了，不用 sort()，一張一張兩兩比較換位置。", "氣泡排序。", "[1, 3, 5, 8]", None),
]

PLACES = {
    "treehouse": "派派鼠的樹屋（主屋）",
    "front_yard": "樹屋前院（信箱、胡蘿蔔園）",
    "sky_top": "天空樹頂",
    "forest_path": "派派森林小徑",
    "creek": "溪畔釣魚角",
    "lavender": "薰衣草原",
    "vault": "螢光寶庫",
    "dungeon": "派森地下城（老樹根下）",
}
NPCS = {"wolf": "派派狼", "rabbit": "派派兔", "crow": "拍拍鳥", "gopher": "派派鼠"}


def build():
    concepts = []
    order = {c[0]: i for i, c in enumerate(CONCEPTS)}
    for cid, area, name, summary, prereqs, tb, needs in CONCEPTS:
        concepts.append({"id": cid, "area": area, "name": name, "summary": summary,
                         "prereqs": prereqs, "textbook": tb,
                         "engine": "ok" if not needs else "needs", "engine_needs": needs})
    needs_of = {c["id"]: c["engine_needs"] for c in concepts}
    tasks = []
    for cid, title, place, npc, diff, story, goal, expected, game in SINGLE:
        area = next(c[1] for c in CONCEPTS if c[0] == cid)
        tid = "Q_" + cid
        n = 2
        while any(t["id"] == tid for t in tasks):
            tid = "Q_%s_%d" % (cid, n)
            n += 1
        tasks.append({"id": tid, "title": title, "concepts": [cid], "compound": False,
                      "difficulty": diff, "area": area, "place": place, "npc": npc,
                      "story": story, "goal": goal, "expected": expected,
                      "status": "playable" if game else ("draft" if not needs_of[cid] else "needs_engine"),
                      "game_task": game, "notes": ""})
    for tid, title, cs, place, npc, diff, story, goal, expected, game in COMPOUND:
        area = max((next(c[1] for c in CONCEPTS if c[0] == x) for x in cs))
        if tid.startswith("K_"):
            area = "K"
        need = sorted({n for x in cs for n in needs_of[x]})
        tasks.append({"id": tid, "title": title, "concepts": cs, "compound": True,
                      "difficulty": diff, "area": area, "place": place, "npc": npc,
                      "story": story, "goal": goal, "expected": expected,
                      "status": "playable" if game else ("draft" if not need else "needs_engine"),
                      "game_task": game, "notes": ""})
    # 舊任務的對應說明
    for t in tasks:
        if t["game_task"] == "T01_print":
            t["notes"] = "舊任務：句型表動作任務，print 的第二個練習。"
        if t["game_task"] in ("D02_acorns", "D03_questions", "T02_variable"):
            t["notes"] = "舊任務一次教好幾個概念，改列為複合任務；單一概念的入門任務在前面。"
    return {
        "schema": 1,
        "world": "派森小鎮",
        "note": "派森小鎮任務書的知識地圖。概念 concepts 用 prereqs 串成先備關係；任務 tasks 一個只教一個概念，"
                "concepts 超過一個的一定是 compound（複合知識）任務。由管理者儀表板或 curriculum-planner Agent 維護。",
        "difficulty_scale": {
            "1": "單一概念，照著句型改一個地方就完成",
            "2": "單一概念，要自己組合句型或處理不同測資",
            "3": "單一概念的進階用法，或兩個熟悉概念的複合應用",
            "4": "複合知識：三個概念或需要自己設計流程",
            "5": "複合知識＋演算法思考（搜尋、排序）",
        },
        "status_names": {"playable": "可以玩", "draft": "草稿（引擎已支援）", "needs_engine": "草稿（要先擴充直譯器）", "idea": "點子"},
        "places": PLACES,
        "npcs": NPCS,
        "areas": [{"id": a, "name": n, "summary": s, "textbook": tb, "color": col, "order": i + 1}
                  for i, (a, n, s, tb, col) in enumerate(AREAS)],
        "concepts": concepts,
        "tasks": tasks,
    }


def validate(m):
    ids = {c["id"] for c in m["concepts"]}
    errs = []
    for c in m["concepts"]:
        for p in c["prereqs"]:
            if p not in ids:
                errs.append(f"{c['id']} 的先備 {p} 不存在")
    # 環狀檢查
    state = {}
    pre = {c["id"]: c["prereqs"] for c in m["concepts"]}

    def visit(n, path):
        if state.get(n) == 1:
            errs.append("先備關係繞圈：" + " → ".join(path + [n]))
            return
        if state.get(n) == 2:
            return
        state[n] = 1
        for p in pre.get(n, []):
            visit(p, path + [n])
        state[n] = 2
    for n in pre:
        visit(n, [])
    for t in m["tasks"]:
        if len(t["concepts"]) > 1 and not t["compound"]:
            errs.append(f"{t['id']} 有多個概念卻沒標 compound")
        if t["compound"] and t["difficulty"] < 3:
            errs.append(f"{t['id']} 是複合任務，難度要 ≥ 3")
        for c in t["concepts"]:
            if c not in ids:
                errs.append(f"{t['id']} 的概念 {c} 不存在")
    single = {t["concepts"][0] for t in m["tasks"] if not t["compound"]}
    for c in ids - single:
        errs.append(f"概念 {c} 沒有單一概念任務")
    return errs


if __name__ == "__main__":
    m = build()
    errs = validate(m)
    if errs:
        print("\n".join(errs))
        sys.exit(1)
    if os.path.exists(OUT) and "--force" not in sys.argv:
        print("已經有 knowledge_map.json，不覆蓋（要重建請加 --force）")
        sys.exit(0)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print(f"寫好了：{len(m['concepts'])} 個概念、{len(m['tasks'])} 個任務")
