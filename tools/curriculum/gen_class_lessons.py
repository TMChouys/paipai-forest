"""把三本教材的簡報文字和習題，依知識點整合成「班級版」圖書館資料。

輸入：教材/（本機才有、不進 git）
輸出：data/class/class_lessons.json（不進 git、公開版匯出不會帶）
      教材/整合對照表.md（給老師檢查：每個知識點收了哪些簡報、哪些習題）

這支程式本身只有分類規則，不含教材內容。
每一張有文字的簡報、每一題習題都會被放進某個知識點（沒有對到的就放在該章的預設知識點），
最後會檢查數量，確保一張都沒漏。

執行：python tools/curriculum/gen_class_lessons.py
"""
import glob
import html
import json
import os
import re
import subprocess
import zipfile
from collections import Counter, OrderedDict, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace('\\', '/') + '/'
SRC = ROOT + '教材/'
OUT = ROOT + 'data/class/class_lessons.json'
REPORT = SRC + '整合對照表.md'

B1 = SRC + '1零基礎入門(簡單)/'
B2 = SRC + '2運算思維(普通)/'
B3 = SRC + '3程式解題(困難)/'
BOOK_NAME = {'入門': '零基礎入門班', '運算思維': '運算思維', '程式解題': '程式解題'}

# ---------------- 新的分類與知識點（知識地圖裡沒有的） ----------------
EXTRA_AREAS = [
    {'id': 'P', 'name': '程式設計入門', 'summary': '運算思維、程式語言、開發環境', 'color': '#e8d6a8', 'order': 0},
    {'id': 'Q', 'name': '進階應用', 'summary': '視窗、圖表、圖片、網路、AI 協作', 'color': '#a8c8e8', 'order': 12},
]
EXTRA_TOPICS = [
    ('ct', 'P', '運算思維與電腦解題', '電腦怎麼解題、解題的步驟'),
    ('lang', 'P', '程式語言與 Python', '高階／低階語言、Python 的特色'),
    ('env', 'P', '開發環境', 'Anaconda、Spyder、IDLE、Jupyter、除錯'),
    ('colab', 'P', 'Google Colab 與 Markdown', '雲端筆記本、Shell 命令、Markdown'),
    ('flow', 'P', '流程圖、演算法與虛擬碼', '把解題步驟畫出來、結構化程式設計'),
    ('ai', 'P', '和 AI 助手一起寫程式', 'Gemini、ChatGPT 協作'),
    ('apcs', 'P', '程式能力檢測', 'APCS、國際認證模擬試題'),
    ('literal', 'B', '物件、常值與保留字', '資料都是物件；常值的寫法；不能當名字的字'),
    ('precedence', 'C', '運算子的優先順序', '誰先算、括號最優先'),
    ('bitwise', 'C', '位元、位移與 in / is 運算子', '& | ^ ~ << >>、in、is'),
    ('fmt_old', 'D', '格式化輸出 % 與 format()', '% 格式碼、str.format()、format()'),
    ('indent', 'E', '程式碼縮排與流程控制', '冒號和縮排決定程式區塊'),
    ('loop_else', 'F', 'for…else 與 while…else', '迴圈正常結束才執行 else'),
    ('list_search', 'G', 'index() 搜尋與 count() 計數', '找位置、數次數'),
    ('list_methods', 'G', '串列的方法與運算子', '串列常用方法總整理'),
    ('list_comp', 'G', '串列生成器', '[運算式 for 變數 in 序列]'),
    ('list2d', 'G', '二維串列', '串列裡面放串列'),
    ('compound_types', 'H', '複合資料型別比較', '串列、元組、字典、集合怎麼選'),
    ('arg_pass', 'I', '引數的傳遞', '傳值、傳參考、傳整個串列'),
    ('recursion', 'I', '遞迴', '函式呼叫自己'),
    ('module_import', 'I', '模組與套件 import', 'import、from…import'),
    ('math_mod', 'I', 'math 模組', '數學函式'),
    ('file_open', 'J', '開啟與關閉檔案', 'open() 的模式、close()、with'),
    ('file_path', 'J', '檔案路徑與資料夾操作', '絕對／相對路徑、os、os.path'),
    ('gui', 'Q', '圖形化使用者介面 tkinter', '視窗、標籤、按鈕、功能表'),
    ('plot', 'Q', '圖表繪製 matplotlib', '線條圖、柱狀圖、圓餅圖'),
    ('numpy', 'Q', 'NumPy 矩陣', '建立矩陣、矩陣運算'),
    ('pillow', 'Q', '圖片處理 pillow', '開圖、濾鏡、縮放、畫圖'),
    ('exe', 'Q', '執行檔建置', 'pyinstaller'),
    ('web_html', 'Q', '網路服務與 HTML', 'WWW、DNS、HTML 標籤'),
    ('crawler', 'Q', '網頁資料擷取', 'urllib、requests、BeautifulSoup、爬蟲'),
]

# ---------------- 簡報的章節 → 知識點 ----------------
# 每章：(預設知識點, {小節編號: 知識點})；小節找不到就往上一層找，再找不到用預設
SLIDE_RULES = {
    '入門': {
        1: ('ct', {'1.3': 'lang', '1.4': 'lang', '1.5': 'env', '1.6': 'env', '1.7': 'colab', '1.7.9': 'ai'}),
        2: ('variable', {'2.1.4': 'comment', '2.2': 'types', '2.2.4': 'convert', '2.3.1': 'print', '2.3.2': 'input',
                         '2.4.1': 'arith', '2.4.2': 'compare', '2.4.3': 'logic', '2.4.4': 'aug_assign',
                         '2.4.5': 'str_concat', '2.4.6': 'precedence'}),
        3: ('if', {'3.1': 'indent', '3.2.1': 'indent', '3.2.2': 'if', '3.2.3': 'if_else', '3.2.4': 'elif', '3.2.5': 'nested_if'}),
        4: ('for_range', {'4.1': 'range_args', '4.2.1': 'nested_loop', '4.2.2': 'break', '4.2.3': 'continue', '4.3': 'while'}),
        5: ('list', {'5.1.3': 'list_index', '5.2': 'for_list', '5.3': 'list_search', '5.4.1': 'list_append',
                     '5.4.2': 'list_remove', '5.5': 'list_sort', '5.6': 'list_methods', '5.7': 'tuple'}),
        6: ('dict', {'6.1.3': 'dict_update', '6.2': 'dict_get', '6.2.3': 'dict_loop', '6.2.4': 'dict_loop'}),
        7: ('def', {'7.1.2': 'param', '7.2': 'builtin', '7.3': 'str_methods', '7.4.1': 'module_import', '7.4': 'random', '7.5': 'time_mod'}),
        8: ('algo', {'8.2': 'bubble', '8.3.1': 'seq_search', '8.3.2': 'binary_search'}),
        9: ('file_open', {'9.1.4': 'file_read', '9.2': 'file_path', '9.2.3': 'try', '9.3': 'try'}),
    },
    '運算思維': {
        0: ('ct', {'0.6': 'apcs'}),
        1: ('lang', {'1.3': 'env', '1.4': 'env'}),
        2: ('variable', {'2.2': 'types', '2.2.2': 'bool', '2.2.4': 'convert', '2.3': 'print', '2.3.1': 'fmt_old',
                         '2.3.2': 'fmt_old', '2.3.3': 'fstring', '2.4': 'input'}),
        3: ('arith', {'3.1': 'reassign', '3.3': 'compare', '3.4': 'logic', '3.5': 'aug_assign'}),
        4: ('if', {'4.1': 'flow', '4.2': 'flow', '4.4': 'if_else', '4.5': 'elif', '4.6': 'nested_if'}),
        5: ('for_range', {'5.2': 'while', '5.3': 'break', '5.4': 'continue', '5.5': 'nested_loop'}),
        6: ('list', {'6.1': 'types', '6.1.1': 'str_index', '6.1.2': 'str_methods', '6.2.2': 'list_methods', '6.3': 'tuple',
                     '6.4': 'dict', '6.4.2': 'dict_update', '6.4.3': 'dict_get', '6.5': 'set', '6.5.3': 'compound_types'}),
        7: ('def', {'7.2': 'param', '7.3': 'return', '7.4': 'arg_pass', '7.5': 'module_import', '7.5.4': 'builtin', '7.6': 'recursion'}),
        8: ('file_path', {'8.2': 'file_open', '8.2.2': 'file_read'}),
        9: ('web_html', {'9.2': 'crawler', '9.3': 'crawler', '9.4': 'crawler', '9.5': 'try'}),
        10: ('gui', {}),
        11: ('plot', {'11.5': 'numpy'}),
        12: ('pillow', {'12.4': 'exe'}),
    },
    '程式解題': {
        1: ('lang', {'1.3': 'flow', '1.4': 'env', '1.5': 'env', '1.6': 'colab'}),
        2: ('literal', {'2.3': 'variable', '2.3.2': 'literal', '2.3.4': 'types', '2.3.5': 'bool', '2.3.6': 'types',
                        '2.4': 'arith', '2.4.1': 'reassign', '2.4.3': 'aug_assign', '2.4.4': 'compare', '2.4.5': 'logic',
                        '2.4.6': 'bitwise', '2.4.7': 'bitwise', '2.4.8': 'bitwise', '2.4.9': 'precedence',
                        '2.5': 'convert', '2.6': 'print'}),
        3: ('types', {'3.2': 'str_concat', '3.2.2': 'str_repeat', '3.2.3': 'str_in', '3.2.4': 'str_index', '3.2.5': 'input',
                      '3.3': 'fmt_old', '3.4': 'str_methods'}),
        4: ('if', {'4.1': 'flow', '4.2': 'compare', '4.3': 'logic', '4.4.2': 'if_else', '4.4.3': 'nested_if', '4.4.4': 'elif'}),
        5: ('for_range', {'5.1': 'range_args', '5.1.3': 'for_range', '5.1.4': 'loop_else', '5.2': 'while', '5.2.2': 'loop_else',
                          '5.3': 'continue', '5.3.2': 'break', '5.4': 'nested_loop', '5.4.2': 'while'}),
        6: ('list', {'6.2.2': 'list_index', '6.3': 'for_list', '6.3.3': 'list_comp', '6.4': 'list_methods', '6.4.4': 'split',
                     '6.5': 'list_sort', '6.6': 'list2d'}),
        7: ('def', {'7.2': 'builtin', '7.2.3': 'math_mod', '7.2.4': 'time_mod', '7.2.5': 'time_mod', '7.3.3': 'param',
                    '7.4': 'arg_pass', '7.5': 'arg_pass', '7.6': 'scope', '7.7': 'recursion'}),
        8: ('tuple', {'8.2': 'dict', '8.2.3': 'dict_get', '8.3': 'set', '8.3.4': 'compound_types'}),
        9: ('file_path', {'9.3': 'file_open', '9.4': 'file_read', '9.5': 'try'}),
        10: ('ai', {}),
        11: ('plot', {}),
        12: ('crawler', {}),
    },
}

# 粗的小節裡，有些投影片其實在講別的知識點：用投影片開頭的字判斷
SLIDE_OVERRIDES = [
    (r'優先順序|優先權', 'precedence'),
    (r'divmod', 'floordiv_mod'),
    (r'區域變數|全域變數|變數有效範圍', 'scope'),
    (r'random|randint|randrange|亂數', 'random'),
    (r'多行註解|單行註解', 'comment'),
    (r'跳脫字元', 'print'),
    (r'map\( *int', 'input'),
    (r'type 指令|type\(', 'types'),
]

# ---------------- 習題的分類：依關鍵字（先找本章用到的知識點） ----------------
EX_RULES = [
    (r'遞迴', 'recursion'),
    (r'tkinter|視窗|Label|Button|messagebox', 'gui'),
    (r'matplotlib|plt\.|柱狀圖|圓餅圖|線條圖|圖表', 'plot'),
    (r'numpy|np\.|矩陣|linspace|arange', 'numpy'),
    (r'pillow|PIL|ImageDraw|ImageFilter|圖片|濾鏡', 'pillow'),
    (r'pyinstaller|執行檔', 'exe'),
    (r'urllib|urlparse|urlopen|requests|BeautifulSoup|爬蟲|爬取|擷取', 'crawler'),
    (r'HTML|DNS|網域|網址|伺服器|全球資訊網|HTTP', 'web_html'),
    (r'ChatGPT|Gemini|AI ', 'ai'),
    (r'Colab|Markdown|Shell', 'colab'),
    (r'Anaconda|Spyder|IDLE|Jupyter|除錯|中斷點|編輯器', 'env'),
    (r'APCS|檢測', 'apcs'),
    (r'流程圖|演算法|虛擬碼|結構化', 'flow'),
    (r'運算思維|電腦解題', 'ct'),
    (r'高階語言|低階語言|編譯|直譯|程式語言', 'lang'),
    (r'泡沫排序|氣泡排序', 'bubble'),
    (r'二分搜尋', 'binary_search'),
    (r'循序搜尋', 'seq_search'),
    (r'try|except|finally|例外', 'try'),
    (r'os\.path|os\.|路徑|資料夾|目錄|mkdir|rmdir', 'file_path'),
    (r'with .* as|close\(|開啟模式|open\(.*["\'][rwa]b?\+?["\']', 'file_open'),
    (r'write|寫入', 'file_write'),
    (r'read|讀取|檔案', 'file_read'),
    (r'global|區域變數|全域變數', 'scope'),
    (r'return|傳回值|回傳', 'return'),
    (r'引數.*傳遞|傳參考|傳值', 'arg_pass'),
    (r'預設值|參數', 'param'),
    (r'def |函式', 'def'),
    (r'random|亂數', 'random'),
    (r'datetime|time\.|時間', 'time_mod'),
    (r'math\.', 'math_mod'),
    (r'import|模組|套件', 'module_import'),
    (r'set\(|集合|union|intersection', 'set'),
    (r'setdefault|\.get\(|keys\(|values\(|items\(', 'dict_get'),
    (r'字典|dict|\{ *[\'"]\w+[\'"] *:', 'dict'),
    (r'tuple|元組', 'tuple'),
    (r'for .* in .* if|\[.* for .* in', 'list_comp'),
    (r'\[ *\[', 'list2d'),
    (r'sort|sorted|reverse', 'list_sort'),
    (r'append|insert|extend', 'list_append'),
    (r'remove|pop\(|del ', 'list_remove'),
    (r'index\(|count\(', 'list_search'),
    (r'split|join', 'split'),
    (r'upper|lower|strip|find\(|replace|startswith|endswith|center|ljust|rjust|zfill', 'str_methods'),
    (r'\[ *-?\d* *: *-?\d* *\]', 'list_slice'),
    (r'串列|list', 'list'),
    (r'for.*else|while.*else', 'loop_else'),
    (r'while', 'while'),
    (r'break', 'break'),
    (r'continue', 'continue'),
    (r'range', 'range_args'),
    (r'for ', 'for_range'),
    (r'elif', 'elif'),
    (r'else', 'if_else'),
    (r'if', 'if'),
    (r'縮排', 'indent'),
    (r'f"|f\'|f-字串', 'fstring'),
    (r'\.format|format\(|%[-0-9.]*[dfsx]', 'fmt_old'),
    (r'input', 'input'),
    (r'\bis\b|<<|>>|位元|&|\^', 'bitwise'),
    (r'\band\b|\bor\b|\bnot\b|邏輯', 'logic'),
    (r'==|!=|>=|<=|關係運算|比較', 'compare'),
    (r'//|divmod|%|餘數|商數', 'floordiv_mod'),
    (r'\+=|-=|\*=|/=|複合指定', 'aug_assign'),
    (r'優先', 'precedence'),
    (r'\*\*|算術|運算', 'arith'),
    (r'int\(|float\(|str\(|轉換', 'convert'),
    (r'type\(|bool|True|False|資料型態|整數|浮點數', 'types'),
    (r'保留字|常值|物件', 'literal'),
    (r'len\(', 'len'),
    (r'變數', 'variable'),
    (r'註解|#', 'comment'),
    (r'print', 'print'),
]

SEC_RE = re.compile(r'^\s*(\d{1,2}(?:[\.\-]\d{1,2}){1,2})\s*[^\d\s\.\-]')
CJK = re.compile(r'[一-鿿]')


def norm_sec(s):
    m = SEC_RE.match(s)
    return m.group(1).replace('-', '.') if m else ''


def chap_of(book, fname):
    m = re.search(r'(\d+)', fname)
    return int(m.group(1)) if m else 0


def lookup(book, chap, secnum):
    default, table = SLIDE_RULES[book].get(chap, ('ct', {}))
    s = secnum
    while s:
        if s in table:
            return table[s]
        s = s.rsplit('.', 1)[0] if '.' in s else ''
    return default


# ---------------- 讀簡報 ----------------
def paras(xml):
    out = []
    for p in re.findall(r'<a:p>(.*?)</a:p>|<a:p [^>]*>(.*?)</a:p>', xml, re.S):
        p = p[0] or p[1]
        t = ''.join(a or b for a, b in re.findall(r'<a:t>(.*?)</a:t>|<a:t [^>]*>(.*?)</a:t>', p, re.S))
        t = html.unescape(t).replace('\u000b', ' ').strip()
        if t:
            out.append(t)
    return out


def read_slides():
    decks = [('入門', B1 + '《Python零基礎入門班(第五版)》教學投影片/*.pptx'),
             ('運算思維', B2 + '*/*.pptx'),
             ('程式解題', B3 + '*/*.pptx')]
    res = []
    for book, pat in decks:
        for f in sorted(glob.glob(pat), key=lambda p: chap_of(book, os.path.basename(p))):
            z = zipfile.ZipFile(f)
            pres = z.read('ppt/presentation.xml').decode('utf8')
            rels = z.read('ppt/_rels/presentation.xml.rels').decode('utf8')
            rid = {}
            for rel in re.findall(r'<Relationship [^>]*>', rels):
                i = re.search(r'Id="(rId\d+)"', rel)
                t = re.search(r'Target="(slides/slide\d+\.xml)"', rel)
                if i and t:
                    rid[i.group(1)] = t.group(1)
            order = [rid[r] for r in re.findall(r'<p:sldId [^>]*r:id="(rId\d+)"', pres) if r in rid]
            name = os.path.splitext(os.path.basename(f))[0]
            chap = chap_of(book, name)
            sec = ''
            for i, s in enumerate(order, 1):
                lines = paras(z.read('ppt/' + s).decode('utf8'))
                for l in lines[:4]:
                    if SEC_RE.match(l) and len(l) < 60:
                        sec = l.strip()
                        break
                lines = [l for l in lines if not re.fullmatch(r'\d{1,3}', l) and l != 'THE END！']
                res.append({'book': book, 'file': name, 'chap': chap, 'n': i, 'sec': sec, 'lines': lines})
    return res


def slide_src(r):
    return '%s 第%d章 第%d張' % (BOOK_NAME[r['book']], r['chap'], r['n'])


# ---------------- 讀習題 ----------------
def pdf_text(p):
    return subprocess.run(['pdftotext', '-enc', 'UTF-8', '-layout', p, '-'], capture_output=True).stdout.decode('utf8', 'replace')


ITEM_MC = re.compile(r'^\s*[\(（]\s*([A-Da-d]{1,4})\s*[\)）]\s*(\d+)\s*[\.．]')
ITEM_QA = re.compile(r'^\s*(\d+)\s*[\.．]\s*\S')


def split_items(lines):
    """把一章的文字切成一題一題：選擇題「( B ) 1.」、問答題「1. …」"""
    items = []
    mode = '選擇題'
    cur = None
    for raw in lines:
        l = raw.rstrip()
        s = l.strip()
        if not s or re.fullmatch(r'\d{1,3}', s):
            continue
        if re.match(r'^(選擇題|問答題|實作題|填充題)[:：]?$', s):
            mode = s.rstrip(':：')
            continue
        m = ITEM_MC.match(l)
        if m:
            cur = {'kind': '選擇題', 'answer': m.group(1).upper(), 'no': int(m.group(2)), 'text': [l[m.end():].strip()]}
            items.append(cur)
            continue
        if mode != '選擇題':
            m = ITEM_QA.match(l)
            if m and not s.startswith('答'):
                cur = {'kind': mode, 'answer': '', 'no': int(m.group(1)), 'text': [s[len(m.group(1)) + 1:].strip()]}
                items.append(cur)
                continue
        if cur is not None:
            cur['text'].append(s if cur['kind'] == '選擇題' else l.strip())
    for it in items:
        if it['kind'] != '選擇題':   # 問答題：「答：」後面是參考答案
            t = '\n'.join(it['text'])
            k = t.find('答：')
            if k < 0:
                k = t.find('答:')
            if k >= 0:
                it['answer'] = t[k + 2:].strip()
                t = t[:k].strip()
            it['text'] = t
        else:
            it['text'] = '\n'.join(it['text']).strip()
    return items


def read_exercises():
    ex = []
    # 入門：綜合演練選擇題（解答檔裡有題目）
    t = pdf_text(B1 + 'Python零基礎入門班(第五版)學習資源/綜合演練/綜合演練-選擇題解答.pdf')
    parts = re.split(r'^\s*Ch(\d{2})\s*$', t, flags=re.M)
    for i in range(1, len(parts), 2):
        ch = int(parts[i])
        for it in split_items(parts[i + 1].splitlines()):
            ex.append(dict(it, book='入門', chap=ch, src='%s 第%d章 綜合演練 選擇題 %d' % (BOOK_NAME['入門'], ch, it['no'])))
    # 入門：綜合演練實作（參考解答程式）、延伸練習
    for folder, label in [('《Python零基礎入門班(第五版)》綜合演練與參考解答', '綜合演練 實作'),
                          ('Python零基礎入門班(第五版)學習資源/延伸練習', '延伸練習')]:
        for f in sorted(glob.glob(B1 + folder + '/ch*/*.py')):
            ch = int(re.search(r'ch(\d+)', f.replace('\\', '/').split('/')[-2]).group(1))
            code = open(f, encoding='utf8', errors='replace').read().strip()
            ex.append({'book': '入門', 'chap': ch, 'kind': label + '（參考程式）', 'answer': '', 'text': '', 'code': code,
                       'src': '%s 第%d章 %s %s' % (BOOK_NAME['入門'], ch, label, os.path.basename(f))})
    # 運算思維：習題題目與解答
    t = pdf_text(B2 + '用Python學程式設計運算思維第二版教學投影片/AEL0248_習題題目與解答(全書).pdf')
    parts = re.split(r'^\s*(第\s*\d+\s*章、.*|附錄\s*A、.*)$', t, flags=re.M)
    for i in range(1, len(parts), 2):
        head = parts[i].strip()
        m = re.search(r'第\s*(\d+)\s*章', head)
        ch = int(m.group(1)) if m else -1
        tag = ('第%d章 習題' % ch) if ch >= 0 else '附錄A 認證模擬試題'
        for it in split_items(parts[i + 1].splitlines()):
            ex.append(dict(it, book='運算思維', chap=ch, src='%s %s %s %d' % (BOOK_NAME['運算思維'], tag, it['kind'], it['no'])))
    return ex


def classify(text, allowed, default):
    for pat, tid in EX_RULES:
        if tid in allowed and re.search(pat, text):
            return tid
    return default


def main():
    kmap = json.load(open(ROOT + 'data/curriculum/knowledge_map.json', encoding='utf8'))
    lessons = json.load(open(ROOT + 'data/curriculum/lessons.json', encoding='utf8'))
    names = {c['id']: c['name'] for c in kmap['concepts'] + lessons['extra_concepts']}
    for tid, area, name, summ in EXTRA_TOPICS:
        names[tid] = name
    all_ids = set(names)

    slides = read_slides()
    # 簡報上寫著範例檔名（例如 <password1.py>）時，把本書範例的程式碼附上（簡報裡的程式多半是圖片）
    examples = {}
    for f in glob.glob(B1 + 'Python零基礎入門班(第五版)學習資源/本書範例/ch*/*.py'):
        examples[os.path.basename(f)] = open(f, encoding='utf8', errors='replace').read().strip()
    content = defaultdict(lambda: {'slides': [], 'exercises': []})
    chap_topics = defaultdict(Counter)    # (book, chap) -> 這一章的簡報用到的知識點
    skipped = 0
    n_code = 0
    exam_slides = []
    for r in slides:
        text = ''.join(r['lines'])
        if not text or re.fullmatch(r'習題|本章結束.*', text) or (r['n'] <= 2 and not r['sec']):   # 封面、章名、結束頁、全是圖片
            skipped += 1
            continue
        tid = lookup(r['book'], r['chap'], norm_sec(r['sec']))
        if re.search(r'檢測模擬試題|程式練習', r['sec']):
            exam_slides.append(r)
            continue
        head = ' '.join(r['lines'][:2])
        for pat, t2 in SLIDE_OVERRIDES:
            if re.search(pat, head):
                tid = t2
                break
        assert tid in all_ids, tid
        chap_topics[(r['book'], r['chap'])][tid] += 1
        item = {'src': slide_src(r), 'sec': r['sec'], 'lines': r['lines']}
        if r['book'] == '入門':
            codes = [(n, examples[n]) for n in dict.fromkeys(re.findall(r'([\w\-]+\.py)', text)) if n in examples]
            if codes:
                item['code'] = [{'file': n, 'code': c} for n, c in codes]
                n_code += len(codes)
        content[tid]['slides'].append(item)

    def chapter_pick(book, chap, text):
        ct = chap_topics.get((book, chap))
        if not ct:
            return classify(text, all_ids, 'apcs')
        return classify(text, set(ct), ct.most_common(1)[0][0])

    for r in exam_slides:                 # 程式解題的檢測模擬試題、運算思維的程式練習 → 當習題
        text = '\n'.join(r['lines'])
        tid = chapter_pick(r['book'], r['chap'], text)
        kind = '檢測模擬試題' if '檢測' in r['sec'] else '程式練習'
        content[tid]['exercises'].append({'src': slide_src(r) + '（' + kind + '）', 'kind': kind, 'text': text, 'answer': ''})

    exercises = read_exercises()
    for e in exercises:
        text = e['text'] + '\n' + e.get('code', '')
        tid = chapter_pick(e['book'], e['chap'], text) if e['chap'] >= 0 else classify(text, all_ids, 'apcs')
        item = {'src': e['src'], 'kind': e['kind'], 'text': e['text'], 'answer': e['answer']}
        if e.get('code'):
            item['code'] = e['code']
        content[tid]['exercises'].append(item)

    # ---- 檢查一張都沒漏 ----
    n_slides = sum(len(v['slides']) for v in content.values())
    n_ex = sum(len(v['exercises']) for v in content.values())
    assert n_slides + len(exam_slides) + skipped == len(slides)
    assert n_ex == len(exam_slides) + len(exercises)

    topics = [{'id': t, 'area': a, 'name': n, 'summary': s} for t, a, n, s in EXTRA_TOPICS]
    out = OrderedDict(schema=1,
                      note='班級版：三本教材的簡報文字與習題，依知識點整合（每則都標出處）。只在本機與班級版使用，不公開。',
                      areas=EXTRA_AREAS, topics=topics,
                      content={k: content[k] for k in sorted(content)})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, 'w', encoding='utf8'), ensure_ascii=False, indent=1)

    # ---- 對照表 ----
    area_of = {c['id']: c['area'] for c in kmap['concepts'] + lessons['extra_concepts']}
    area_of.update({t: a for t, a, n, s in EXTRA_TOPICS})
    area_name = {a['id']: a['name'] for a in kmap['areas'] + EXTRA_AREAS}
    area_order = {a['id']: a['order'] for a in kmap['areas'] + EXTRA_AREAS}
    with open(REPORT, 'w', encoding='utf8') as f:
        f.write('# 班級版圖書館：簡報與習題整合對照表\n\n')
        f.write('由 tools/curriculum/gen_class_lessons.py 產生。簡報 %d 張（另有 %d 張是封面／章名／結束頁，或整張都是圖片沒有文字）、習題 %d 題，全部都放進下面的知識點。\n\n'
                % (n_slides + len(exam_slides), skipped, n_ex))
        for tid in sorted(content, key=lambda t: (area_order[area_of[t]], t)):
            v = content[tid]
            f.write('## %s %s・%s（`%s`）\n\n' % (area_of[tid], area_name[area_of[tid]], names[tid], tid))
            secs = OrderedDict()
            for s in v['slides']:
                key = s['src'].rsplit(' 第', 1)[0] + '｜' + (s['sec'] or '（章首）')
                secs.setdefault(key, []).append(s['src'].rsplit(' ', 1)[1])
            for k, ns in secs.items():
                f.write('- 簡報 %s：%s\n' % (k, '、'.join(ns)))
            for e in v['exercises']:
                f.write('- 習題 %s\n' % e['src'])
            f.write('\n')
    print('簡報 %d 張（跳過封面 %d）、模擬試題／練習投影片 %d、習題 %d 題 → %d 個知識點' %
          (n_slides, skipped, len(exam_slides), len(exercises), len(content)))
    print('附上本書範例程式 %d 個' % n_code)
    print('沒有任何教材內容的知識點：', [t for t in sorted(all_ids) if t not in content])


if __name__ == '__main__':
    main()
