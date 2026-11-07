"""檢查 data/curriculum/knowledge_map.json。用法：python -I tools/curriculum/check_map.py"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(ROOT, "data", "curriculum", "knowledge_map.json")


def check(m):
    errs = []
    areas = {a["id"] for a in m["areas"]}
    ids = [c["id"] for c in m["concepts"]]
    idset = set(ids)
    if len(ids) != len(idset):
        errs.append("概念 id 重複")
    pre = {}
    for c in m["concepts"]:
        if c["area"] not in areas:
            errs.append(f"概念 {c['id']} 的範圍 {c['area']} 不存在")
        for p in c["prereqs"]:
            if p not in idset:
                errs.append(f"概念 {c['id']} 的先備 {p} 不存在")
        pre[c["id"]] = c["prereqs"]
    state = {}

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
    tids = [t["id"] for t in m["tasks"]]
    if len(tids) != len(set(tids)):
        errs.append("任務 id 重複")
    for t in m["tasks"]:
        if not t["concepts"]:
            errs.append(f"任務 {t['id']} 沒有概念")
        if len(t["concepts"]) > 1 and not t["compound"]:
            errs.append(f"任務 {t['id']} 有多個概念，要標成複合任務")
        if t["compound"] and int(t["difficulty"]) < 3:
            errs.append(f"任務 {t['id']} 是複合任務，難度要 ≥ 3")
        if not 1 <= int(t["difficulty"]) <= 5:
            errs.append(f"任務 {t['id']} 難度要是 1–5")
        for c in t["concepts"]:
            if c not in idset:
                errs.append(f"任務 {t['id']} 的概念 {c} 不存在")
        if t["place"] not in m["places"]:
            errs.append(f"任務 {t['id']} 的地點 {t['place']} 不在 places")
        if t["npc"] not in m["npcs"]:
            errs.append(f"任務 {t['id']} 的角色 {t['npc']} 不在 npcs")
        g = t.get("game_task")
        if g and not os.path.exists(os.path.join(ROOT, "data", "tasks", g + ".json")):
            errs.append(f"任務 {t['id']} 的 game_task {g} 找不到檔案")
        if t["status"] == "playable" and not g:
            errs.append(f"任務 {t['id']} 標成可以玩，但沒有 game_task")
    single = {t["concepts"][0] for t in m["tasks"] if not t["compound"] and t["concepts"]}
    for c in idset - single:
        errs.append(f"概念 {c} 還沒有單一概念任務")
    return errs


if __name__ == "__main__":
    m = json.load(open(PATH, encoding="utf-8"))
    errs = check(m)
    sys.stdout.reconfigure(encoding="utf-8")
    if errs:
        print("\n".join(errs))
        sys.exit(1)
    print(f"OK：{len(m['concepts'])} 個概念、{len(m['tasks'])} 個任務")
