"""教材關係總檢查：知識地圖（館長）× 上課（派派兔）× 冒險委託（派派狼）。

規則（2026-11-08 整理）：
  1. 慢慢館長的知識地圖：全部都可以看，不限制。
  2. 派派兔的上課：先修課（knowledge_map 的 prereqs ＋ classes.json 的 extra_prereqs）都通過了，這一課才開。
  3. 派派狼的冒險委託：任務程式裡「實際用到」的每一個概念都要先上過課，委託才解鎖（任務 JSON 的 lessons）。
     例外：第一個任務〈嘿！新來的〉（print()）在派派鼠家裡就能做，lessons = []。
     主線任務另外照順序（story），支線和野外冒險只看上過的課。

這支工具：
  - 把每個任務的參考答案（reference）拆成語法樹，找出實際用到的概念；
  - 檢查任務 JSON 的 lessons 和實際用到的一樣（--fix 會直接寫回）；
  - 檢查上課的先修關係沒有循環、每一課都上得到、每個任務需要的課都上得到；
  - 輸出 docs/curriculum/教材關係總表.md。
用法：python tools/curriculum/audit.py [--fix]
"""
import ast
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
J = lambda p: json.load(open(os.path.join(ROOT, p), encoding="utf-8"))
KM = J("data/curriculum/knowledge_map.json")
LS = J("data/curriculum/lessons.json")
CL = J("data/curriculum/classes.json")
LESSONS = LS["lessons"]
CONCEPTS = {c["id"]: c for c in KM["concepts"]}
for c in LS.get("extra_concepts", []):
    CONCEPTS.setdefault(c["id"], c)
NO_LESSON_TASKS = {"D01_hello"}


def prereqs(cid):
    return [p for p in CONCEPTS.get(cid, {}).get("prereqs", []) + CL.get("extra_prereqs", {}).get(cid, []) if p in LESSONS]


# ---------------- 程式 → 用到的概念 ----------------
def concepts_in(code: str) -> set:
    tree = ast.parse(code)
    used = set()
    types = {}          # 變數名稱 → "str" / "list" / "dict" / "num"
    assigned = {}

    def kind_of(v):
        if isinstance(v, ast.Constant):
            return "str" if isinstance(v.value, str) else ("bool" if isinstance(v.value, bool) else "num")
        if isinstance(v, (ast.List, ast.ListComp)):
            return "list"
        if isinstance(v, ast.Dict):
            return "dict"
        if isinstance(v, ast.Tuple):
            return "tuple"
        if isinstance(v, ast.JoinedStr):
            return "str"
        if isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute) and v.func.attr == "split":
            return "list"
        return ""

    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    assigned[t.id] = assigned.get(t.id, 0) + 1
                    k = kind_of(node.value)
                    if k:
                        types[t.id] = k
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            f = node.func.id
            if f == "print":
                used.add("print")
                if len(node.args) > 1 or node.keywords:
                    used.add("print_multi")
            elif f in ("int", "float", "str"):
                inner = node.args[0] if node.args else None
                if isinstance(inner, ast.Call) and isinstance(inner.func, ast.Name) and inner.func.id == "input":
                    used.add("input_number")
                else:
                    used.add("convert")
            elif f == "input":
                used.add("input")
            elif f == "len":
                used.add("len")
            elif f in ("max", "min", "abs", "round", "sum", "divmod", "pow"):
                used.add("builtin")
            elif f == "sorted":
                used.add("list_sort")
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            a = node.func.attr
            m = {"append": "list_append", "insert": "list_append", "remove": "list_remove", "pop": "list_remove",
                 "sort": "list_sort", "split": "split", "join": "split", "get": "dict_get", "items": "dict_loop",
                 "keys": "dict_loop", "values": "dict_loop", "count": "list_in", "index": "list_in",
                 "startswith": "str_methods", "endswith": "str_methods", "find": "str_methods", "replace": "str_methods",
                 "strip": "str_methods", "upper": "str_methods", "lower": "str_methods",
                 "randint": "random", "choice": "random", "sleep": "time_mod"}
            if a in m:
                used.add(m[a])
        if isinstance(node, ast.Assign) or isinstance(node, ast.AnnAssign):
            used.add("variable")
        if isinstance(node, ast.Constant) and isinstance(node.value, bool):
            used.add("bool")
        if isinstance(node, ast.BinOp):
            str_side = any(isinstance(s, ast.Constant) and isinstance(s.value, str) or
                           (isinstance(s, ast.Name) and types.get(s.id) == "str") or isinstance(s, ast.JoinedStr)
                           for s in (node.left, node.right))
            if isinstance(node.op, (ast.FloorDiv, ast.Mod)):
                used.add("floordiv_mod")
            elif isinstance(node.op, ast.Add) and str_side:
                used.add("str_concat")
            elif isinstance(node.op, ast.Mult) and str_side:
                used.add("str_repeat")
            else:
                used.add("arith")
        if isinstance(node, ast.AugAssign):
            used.add("aug_assign")
        if isinstance(node, ast.Compare):
            for op in node.ops:
                if isinstance(op, (ast.In, ast.NotIn)):
                    right = node.comparators[0]
                    is_str = (isinstance(right, ast.Constant) and isinstance(right.value, str)) or \
                             (isinstance(right, ast.Name) and types.get(right.id) == "str")
                    used.add("str_in" if is_str else "list_in")
                else:
                    used.add("compare")
        if isinstance(node, (ast.BoolOp,)) or (isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not)):
            used.add("logic")
        if isinstance(node, ast.JoinedStr):
            used.add("fstring")
        if isinstance(node, ast.Subscript):
            v = node.value
            k = types.get(v.id, "") if isinstance(v, ast.Name) else ""
            if isinstance(node.slice, ast.Slice):
                used.add("list_slice")
            elif k == "str":
                used.add("str_index")
            elif k == "dict":
                used.add("dict")
                if isinstance(node.ctx, ast.Store):
                    used.add("dict_update")
            else:
                used.add("list_index")
        if isinstance(node, ast.List):
            used.add("list")
        if isinstance(node, ast.Dict):
            used.add("dict")
        if isinstance(node, ast.Tuple) and isinstance(getattr(node, "ctx", None), ast.Load):
            pass
        if isinstance(node, ast.If):
            used.add("if")
            if node.orelse:
                if len(node.orelse) == 1 and isinstance(node.orelse[0], ast.If):
                    used.add("elif")
                else:
                    used.add("if_else")
            for b in node.body:
                if isinstance(b, ast.If):
                    used.add("nested_if")
        if isinstance(node, ast.For):
            it = node.iter
            if isinstance(it, ast.Call) and isinstance(it.func, ast.Name) and it.func.id == "range":
                used.add("for_range")
                if len(it.args) > 1:
                    used.add("range_args")
            elif isinstance(it, ast.Call) and isinstance(it.func, ast.Attribute) and it.func.attr == "items":
                used.add("dict_loop")
            elif isinstance(it, ast.Name) and types.get(it.id) == "str" or isinstance(it, ast.Constant):
                used.add("for_str")
            else:
                used.add("for_list")
            for sub in ast.walk(node):
                if isinstance(sub, ast.AugAssign):
                    used.add("accumulate")
                if sub is not node and isinstance(sub, (ast.For, ast.While)):
                    used.add("nested_loop")
        if isinstance(node, ast.While):
            used.add("while")
        if isinstance(node, ast.Break):
            used.add("break")
        if isinstance(node, ast.Continue):
            used.add("continue")
        if isinstance(node, ast.FunctionDef):
            used.add("def")
            if node.args.args:
                used.add("param")
        if isinstance(node, ast.Return):
            used.add("return")
        if isinstance(node, ast.Try):
            used.add("try")
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            for n in node.names if isinstance(node, ast.Import) else [ast.alias(node.module)]:
                if n.name == "random":
                    used.add("random")
                if n.name in ("time", "datetime"):
                    used.add("time_mod")
    if any(n > 1 for n in assigned.values()):
        used.add("reassign")
    import io, tokenize
    if any(tok.type == tokenize.COMMENT for tok in tokenize.generate_tokens(io.StringIO(code).readline)):
        used.add("comment")
    return {u for u in used if u in LESSONS}


def topo_order(ids):
    order, seen, stack = [], set(), set()

    def visit(c):
        if c in stack:
            raise SystemExit("先修關係有循環：" + c)
        if c in seen:
            return
        stack.add(c)
        for p in prereqs(c):
            visit(p)
        stack.discard(c)
        seen.add(c)
        order.append(c)
    for c in ids:
        visit(c)
    return order


def closure(cs):
    out = set()
    todo = list(cs)
    while todo:
        c = todo.pop()
        if c in out:
            continue
        out.add(c)
        todo += prereqs(c)
    return out


def main():
    fix = "--fix" in sys.argv
    errors = []
    order = topo_order(list(LESSONS))   # 也檢查沒有循環
    tasks = []
    for f in sorted(glob.glob(os.path.join(ROOT, "data/tasks/*.json"))):
        t = json.load(open(f, encoding="utf-8"))
        used = concepts_in(t["reference"])
        want = [] if t["id"] in NO_LESSON_TASKS else [c for c in order if c in used]
        have = t.get("lessons")
        if have != want:
            if fix:
                # 只改 lessons 這一行（其他排版不動）
                txt = open(f, encoding="utf-8", newline="").read()
                line = '"lessons": ' + json.dumps(want, ensure_ascii=False)
                if re.search(r'"lessons":\s*\[[^\]]*\]', txt):
                    txt = re.sub(r'"lessons":\s*\[[^\]]*\]', lambda m: line, txt, count=1)
                else:
                    txt = re.sub(r'("id":\s*"[^"]*",)', lambda m: m.group(1) + "\n  " + line + ",", txt, count=1)
                assert json.loads(txt)["lessons"] == want, t["id"]
                open(f, "w", encoding="utf-8", newline="").write(txt)
            else:
                errors.append(f"{t['id']}：lessons {have} ≠ 實際用到 {want}")
        tasks.append((t, want))
    for cid in LESSONS:
        if cid not in CONCEPTS:
            errors.append("上課有、知識地圖沒有：" + cid)
    for cid in LESSONS:
        if cid not in CL.get("classes", {}):
            errors.append("這一課沒有安排老師和故事：" + cid)
    # 報告
    names = lambda cs: "、".join(CONCEPTS[c]["name"] for c in cs) or "（不用先上課）"
    tn = CL.get("teacher_names", {})
    md = ["# 教材關係總表（tools/curriculum/audit.py 產生，不要手改）", "",
          "## 限制與開放", "",
          "| 地方 | 誰 | 能不能看／做 |", "|---|---|---|",
          "| 知識地圖 | 慢慢館長 | **全部都可以看**，不限制 |",
          "| 上課 | 派派兔（老師依故事安排） | 先修課都通過（小測驗全對）才開 |",
          "| 冒險委託 | 派派狼 | 任務程式實際用到的每一課都上過才解鎖；主線照順序；第一個任務〈嘿！新來的〉不用先上課 |",
          "", "## 冒險委託需要的課", "",
          "| 任務 | 類別 | 地點 | 要先上的課（實際用到） | 一共要上幾堂（含先修） |", "|---|---|---|---|---|"]
    for t, want in sorted(tasks, key=lambda x: int(x[0]["order"])):
        md.append("| %s %s | %s | %s | %s | %d |" % (t["id"], t["title"], {"main": "主線", "side": "支線", "adventure": "野外冒險"}.get(t.get("track", "main"), ""),
                                                  t.get("place", t["room"].get("name", "")), names(want), len(closure(want))))
    md += ["", "## 每一課：老師、故事、用到這一課的委託", "",
           "| 課 | 先修 | 老師 | 故事 | 冒險委託 |", "|---|---|---|---|---|"]
    for cid in order:
        cl = CL["classes"].get(cid, {})
        users = [t["title"] for t, w in tasks if cid in w]
        md.append("| %s | %s | %s | %s | %s |" % (CONCEPTS[cid]["name"], names(prereqs(cid)) if prereqs(cid) else "—",
                                                tn.get(cl.get("teacher", ""), ""), cl.get("story", ""), "、".join(users) or "—"))
    no_task = [CONCEPTS[c]["name"] for c in order if not any(c in w for t, w in tasks)]
    md += ["", "## 還沒有冒險委託的課（之後補任務）", "", "、".join(no_task), ""]
    os.makedirs(os.path.join(ROOT, "docs/curriculum"), exist_ok=True)
    open(os.path.join(ROOT, "docs/curriculum/教材關係總表.md"), "w", encoding="utf-8").write("\n".join(md))
    for t, want in sorted(tasks, key=lambda x: int(x[0]["order"])):
        print(f"{t['id']:22s} 用到 {len(want):2d} 課，含先修 {len(closure(want)):2d}：{names(want)}")
    print("還沒有委託的課：", len(no_task))
    if errors:
        print("\n".join("✗ " + e for e in errors))
        sys.exit(1)
    print("✓ 全部一致")


if __name__ == "__main__":
    main()
