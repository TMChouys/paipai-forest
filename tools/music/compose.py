"""背景音樂：用程式寫譜（旋律、和弦、伴奏），再用 FluidSynth＋GeneralUser GS 音色庫播成音檔。

為什麼不用 AI 生成：要能控制每一個音——吉他只用撥的（不滑弦、不磨弦），
過關音樂結尾要往上揚，也不能有突然冒出來的怪音。

環境：
  FluidSynth   D:/ai/fluidsynth/fluidsynth-v2.6.2-win10-x64-cpp11/bin/fluidsynth.exe（官方 GitHub release）
  音色庫       D:/ai/soundfonts/GeneralUser-GS.sf2（S. Christian Collins，免費、可商用）
  Python       numpy、soundfile（D:/ai/musicgen 這個 venv 裡就有）
用法：D:/ai/musicgen/Scripts/python tools/music/compose.py [曲名 ...]
輸出：audio/music/<曲名>.ogg；循環曲取第二遍，讓殘響接回開頭，循環點聽不出接縫。
"""
import os
import random
import struct
import subprocess
import sys

import numpy as np
import soundfile as sf

FLUID = "D:/ai/fluidsynth/fluidsynth-v2.6.2-win10-x64-cpp11/bin/fluidsynth.exe"
SF2 = "D:/ai/soundfonts/GeneralUser-GS.sf2"
SR = 44100
TPB = 480  # 每拍 tick 數
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = os.path.join(ROOT, "audio", "music")
WORK = "D:/ai/music_work"

# General MIDI 音色（0 起算）
PIANO, CELESTA, GLOCK, VIBES, MARIMBA, XYLO = 0, 8, 9, 11, 12, 13
ACCORDION, NYLON, AC_BASS, PIZZ = 21, 24, 32, 45
STRINGS, SLOW_STR, HORN, FLUTE = 48, 49, 60, 73
EPIANO = 4

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUAL = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11),
        "m7": (0, 3, 7, 10), "sus": (0, 5, 7)}


def pitch(name: str) -> int:
    """'C5'、'Bb4'、'F#3' → MIDI 音高（C4 = 60）"""
    n = NOTE[name[0]]
    i = 1
    while name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


def chord(sym: str) -> tuple[int, tuple]:
    """'F'、'Dm'、'C/E'、'Fmaj7' → (根音音級, 音程)；斜線後面是低音"""
    bass = None
    if "/" in sym:
        sym, b = sym.split("/")
        bass = NOTE[b[0]] + (1 if "#" in b else -1 if "b" in b[1:] else 0)
    r = NOTE[sym[0]]
    i = 1
    if i < len(sym) and sym[i] in "#b":
        r += 1 if sym[i] == "#" else -1
        i += 1
    q = QUAL[sym[i:]]
    return r % 12, q, (bass if bass is not None else r) % 12


def near(pc: int, around: int) -> int:
    """音級 pc 最靠近 around 的那個音高"""
    p = around - ((around - pc) % 12)
    return p + 12 if around - p > 6 else p


class Song:
    def __init__(self, bpm: float, beats_per_bar: int = 4, seed: int = 1):
        self.bpm = bpm
        self.bpb = beats_per_bar
        self.parts = {}  # 聲道 → dict(program, vol, pan, rev, notes)
        self.rng = random.Random(seed)

    def part(self, ch: int, program: int, vol: int = 100, pan: int = 64, rev: int = 60):
        self.parts[ch] = {"program": program, "vol": vol, "pan": pan, "rev": rev, "notes": [], "expr": []}
        return ch

    def note(self, ch, beat, dur, p, vel):
        v = max(1, min(127, int(vel + self.rng.uniform(-5, 5))))
        self.parts[ch]["notes"].append((beat, dur, p, v))

    def melody(self, ch, bar, text, vel=80, octave=0, legato=0.92, accent=6):
        """'C5:1.5 A4:.5 r:1' 從第 bar 小節開始寫；回傳寫了幾拍"""
        b = bar * self.bpb
        for tok in text.split():
            n, d = tok.split(":")
            d = float(d)
            if n != "r":
                # 句子的第一拍稍微重一點，聽起來比較有呼吸
                acc = accent if abs((b % self.bpb)) < 1e-6 else 0
                self.note(ch, b, d * legato, pitch(n) + 12 * octave, vel + acc)
            b += d
        return b - bar * self.bpb

    def expr(self, ch, beat, value):
        self.parts[ch]["expr"].append((beat, value))

    # ---- MIDI 檔 ----
    def midi(self, path: str, repeat: int = 1, total_beats: float = 0):
        ev = []
        tempo = int(round(60_000_000 / self.bpm))
        ev.append((0, 0, bytes([0xFF, 0x51, 3]) + tempo.to_bytes(3, "big")))
        for ch, pt in self.parts.items():
            ev.append((0, 1, bytes([0xC0 | ch, pt["program"]])))
            for cc, val in ((7, pt["vol"]), (10, pt["pan"]), (91, pt["rev"]), (93, 0), (11, 127)):
                ev.append((0, 2, bytes([0xB0 | ch, cc, val])))
            for k in range(repeat):
                off = k * total_beats
                for beat, val in pt["expr"]:
                    ev.append((int(round((beat + off) * TPB)), 3, bytes([0xB0 | ch, 11, val])))
                for beat, dur, p, v in pt["notes"]:
                    t0 = int(round((beat + off) * TPB))
                    t1 = int(round((beat + off + dur) * TPB))
                    ev.append((t0, 5, bytes([0x90 | ch, p, v])))
                    ev.append((t1, 4, bytes([0x80 | ch, p, 0])))
        ev.sort(key=lambda e: (e[0], e[1]))
        data = bytearray()
        last = 0
        for t, _, msg in ev:
            data += vlq(t - last) + msg
            last = t
        data += vlq(TPB * 8) + bytes([0xFF, 0x2F, 0])  # 結尾多留兩小節給殘響
        with open(path, "wb") as f:
            f.write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, TPB))
            f.write(b"MTrk" + struct.pack(">I", len(data)) + data)


def vlq(n: int) -> bytes:
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def render(song: Song, name: str, beats: float, loop: bool) -> np.ndarray:
    os.makedirs(WORK, exist_ok=True)
    mid = f"{WORK}/{name}.mid"
    wav = f"{WORK}/{name}_raw.wav"
    song.midi(mid, repeat=2 if loop else 1, total_beats=beats)
    subprocess.run([FLUID, "-ni", "-q", "-g", "0.5", "-r", str(SR),
                    "-o", "synth.chorus.active=0",
                    "-o", "synth.reverb.room-size=0.62", "-o", "synth.reverb.damp=0.35",
                    "-o", "synth.reverb.width=0.9", "-o", "synth.reverb.level=0.55",
                    "-F", wav, SF2, mid], check=True, stdin=subprocess.DEVNULL)
    a, sr = sf.read(wav, dtype="float64")
    assert sr == SR
    L = int(round(beats * 60.0 / song.bpm * SR))
    if loop:
        d = int(SR * 0.01)   # 提早 10 毫秒切：接縫落在音頭前面的安靜處，不會切到撥弦的音頭
        a = a[L - d:2 * L - d]  # 第二遍：開頭已經帶著上一遍的殘響，循環接起來沒有縫
    else:
        # 去掉尾巴的靜音，最後 0.4 秒淡出
        level = np.abs(a).max(axis=1)
        end = int(np.nonzero(level > 1e-4)[0][-1]) + 1
        a = a[:end]
        n = min(len(a), int(SR * 0.4))
        a[-n:] *= np.linspace(1.0, 0.0, n)[:, None] ** 2
    return a


def finish(a: np.ndarray, target_rms: float) -> np.ndarray:
    rms = np.sqrt(np.mean(a ** 2)) + 1e-9
    a = a * (target_rms / rms)
    peak = np.abs(a).max()
    if peak > 0.89:
        a = a * (0.89 / peak)
    return a.astype(np.float32)


def write_ogg(path: str, a: np.ndarray) -> None:
    """分段寫入：libsndfile 一次寫很長的 Vorbis 會當掉。"""
    with sf.SoundFile(path, "w", SR, a.shape[1], format="OGG", subtype="VORBIS") as f:
        f.write(a[:1])
        for i in range(1, len(a), 4096):
            f.write(a[i:i + 4096])


# ---------------------------------------------------------------- 伴奏工具
def guitar_arp(s: Song, ch, bar, chords, vel=58, low=40):
    """指彈分解和弦（一個音一個音撥，讓它自然延音，不滑弦）"""
    for i, sym in enumerate(chords):
        r, q, bass = chord(sym)
        b0 = (bar + i) * s.bpb
        lo = near(bass, low + 4)
        if lo < low:
            lo += 12
        tones = sorted({near((r + iv) % 12, lo + 12 + k * 4) for k, iv in enumerate(q[:3])})
        third, fifth = tones[1 % len(tones)], tones[-1]
        top = near(r, lo + 19)
        pat = [lo, tones[0], third, fifth, top, fifth, third, tones[0]]
        for k, p in enumerate(pat):
            v = vel + (8 if k == 0 else 0) - (4 if k % 2 else 0)
            s.note(ch, b0 + k * 0.5, 1.6 if k else 3.0, p, v)


def pad(s: Song, ch, bar, chords, vel=42, center=60):
    for i, sym in enumerate(chords):
        r, q, _ = chord(sym)
        for iv in q[1:]:
            s.note(ch, (bar + i) * s.bpb, s.bpb - 0.05, near((r + iv) % 12, center), vel)
        s.note(ch, (bar + i) * s.bpb, s.bpb - 0.05, near(r, center - 7), vel - 4)


def bass_line(s: Song, ch, bar, chords, vel=62, low=36):
    for i, sym in enumerate(chords):
        r, q, bass = chord(sym)
        p = near(bass, low + 6)
        b0 = (bar + i) * s.bpb
        s.note(ch, b0, 1.7, p, vel)
        s.note(ch, b0 + 2, 1.7, near((r + q[2]) % 12, p + 5), vel - 8)


# ---------------------------------------------------------------- 曲子
def rhodes_comp(s: Song, ch, bar, chords, vel=40, center=62):
    """電鋼琴輕輕按和弦：第一拍長按，第三拍後半輕輕再按一次（像咖啡廳裡的伴奏）"""
    for i, sym in enumerate(chords):
        r, q, _ = chord(sym)
        b0 = (bar + i) * s.bpb
        voice = sorted({near((r + iv) % 12, center + k * 3) for k, iv in enumerate(q[1:] + (0,))})
        for k, p in enumerate(voice):
            s.note(ch, b0 + k * 0.015, 2.3, p, vel)
            s.note(ch, b0 + 2.5 + k * 0.015, 1.4, p, vel - 8)


def home() -> tuple[Song, float]:
    """樹屋：F 大調 76 bpm。電鋼琴（Rhodes）唱旋律＋尼龍弦吉他指彈，木貝斯和很輕的弦樂墊底。
    溫暖、明亮的大調（maj7 和弦），像午後的咖啡廳：療癒、可以發呆，慢慢佈置家具也不用心急。
    放置型遊戲的背景音樂：六段輪流換主角（吉他、電鋼琴、貝斯進出），長時間聽也不膩。48 小節約 2 分 32 秒循環。"""
    s = Song(76, seed=53)
    gtr = s.part(0, NYLON, vol=96, pan=50, rev=55)
    epl = s.part(1, EPIANO, vol=92, pan=72, rev=62)      # 電鋼琴旋律
    epc = s.part(2, EPIANO, vol=78, pan=60, rev=62)      # 電鋼琴和弦
    bas = s.part(3, AC_BASS, vol=78, pan=60, rev=30)
    pad_ = s.part(4, SLOW_STR, vol=46, pan=40, rev=80)
    gtm = s.part(5, NYLON, vol=90, pan=78, rev=55)       # 吉他唱旋律的那一段
    A = ["Fmaj7", "C/E", "Dm7", "Bbmaj7", "F", "Gm7", "C", "F"]
    B = ["Bbmaj7", "C", "Am7", "Dm7", "Gm7", "C", "Bbmaj7", "C"]
    mA = ("A4:1.5 C5:.5 E5:1 C5:1  D5:1.5 C5:.5 G4:2  F4:1 A4:1 C5:1 D5:1  D5:3 r:1 "
          "C5:1.5 A4:.5 F5:1 E5:1  D5:1.5 Bb4:.5 G4:2  E4:1 G4:1 Bb4:1 E5:1  F5:3 r:1")
    mA2 = ("A4:1 C5:1 F5:1.5 E5:.5  D5:1 C5:1 G4:2  A4:1 C5:1 F5:1 D5:1  D5:2 F5:2 "
           "C5:1.5 A4:.5 F5:1 E5:1  D5:1.5 Bb4:.5 G4:2  G4:1 C5:1 E5:1 G5:1  F5:3 r:1")
    mB = ("F5:1.5 D5:.5 Bb4:2  C5:1 E5:1 G5:2  E5:1.5 C5:.5 A4:2  F5:1 E5:1 D5:1 C5:1 "
          "Bb4:1.5 D5:.5 F5:2  E5:1 D5:1 C5:2  D5:1 F5:1 A5:1.5 F5:.5  G5:2 E5:1 C5:1")
    cA = "C6:4 C6:4 A5:4 F5:4 A5:4 Bb5:4 G5:4 A5:2 r:2"   # 電鋼琴高高的長音（尾段點綴）
    for k in range(6):
        bar = k * 8
        chords = B if k == 3 else A
        guitar_arp(s, gtr, bar, chords, vel=54 if k in (0, 5) else 48)
        if k == 0:
            rhodes_comp(s, epc, bar, chords, vel=36)
        elif k == 1:
            s.melody(epl, bar, mA, vel=66, legato=0.95, accent=4)
        elif k == 2:
            s.melody(epl, bar, mA2, vel=66, legato=0.95, accent=4)
            bass_line(s, bas, bar, chords, vel=54)
        elif k == 3:
            s.melody(epl, bar, mB, vel=68, legato=0.95, accent=4)
            bass_line(s, bas, bar, chords, vel=56)
            pad(s, pad_, bar, chords, vel=34, center=60)
        elif k == 4:
            s.melody(gtm, bar, mA, vel=70, legato=1.0, accent=4)   # 換吉他唱
            rhodes_comp(s, epc, bar, chords, vel=34)
            bass_line(s, bas, bar, chords, vel=50)
        else:
            s.melody(epl, bar, cA, vel=48, legato=1.0, accent=0)
            pad(s, pad_, bar, chords, vel=26, center=60)
    return s, 48 * 4


def town() -> tuple[Song, float]:
    """派森小鎮：G 大調 100 bpm。手風琴＋木琴旋律，撥奏弦樂和吉他輕快地打拍子。32 小節"""
    s = Song(100, seed=23)
    acc = s.part(0, ACCORDION, vol=78, pan=58, rev=50)
    mar = s.part(1, MARIMBA, vol=96, pan=78, rev=55)
    piz = s.part(2, PIZZ, vol=92, pan=44, rev=45)
    gtr = s.part(3, NYLON, vol=86, pan=84, rev=45)
    A = ["G", "D", "Em", "C", "G", "C", "D", "G"]
    B = ["C", "D", "Bm", "Em", "C", "D", "G/B", "D7"]
    mA = ("D5:.5 B4:.5 G4:1 B4:.5 D5:.5 G5:1  F#5:1 E5:.5 D5:.5 A4:2  E5:.5 G5:.5 E5:.5 B4:.5 E5:1 D5:1  C5:1 E5:1 G5:2 "
          "B4:.5 D5:.5 G5:.5 D5:.5 B4:1 G4:1  A4:.5 C5:.5 E5:.5 C5:.5 G5:1 E5:1  D5:1 F#5:1 A5:.5 F#5:.5 E5:1  G5:2 r:2")
    mB = ("E5:1.5 D5:.5 C5:1 E5:1  F#5:1.5 E5:.5 D5:2  D5:1 B4:1 F#5:1.5 D5:.5  E5:2 G5:2 "
          "G5:1 E5:.5 G5:.5 A5:1 G5:1  F#5:1 D5:1 A4:1 F#5:1  G5:1 D5:1 E5:1 C5:1  A4:1 B4:.5 C5:.5 D5:1 F#4:1")

    def oompah(bar, chords, vel=70):
        for i, sym in enumerate(chords):
            r, q, bass = chord(sym)
            b0 = (bar + i) * 4
            lo = near(bass, 48)  # 撥奏低音不要太低，太低會「咚」一聲很突兀
            s.note(piz, b0, 0.5, lo, vel - 12)
            s.note(piz, b0 + 2, 0.5, near((r + q[2]) % 12, lo + 5), vel - 18)
            for beat in (1, 3):
                # 吉他在反拍輕輕撥一個和弦（三個音幾乎同時，由低到高）
                for k, iv in enumerate(q[:3]):
                    s.note(gtr, b0 + beat + k * 0.02, 0.45, near((r + iv) % 12, 57 + k * 4), vel - 20)

    for k, (chords, m) in enumerate([(A, mA), (A, mA), (B, mB), (A, mA)]):
        bar = k * 8
        oompah(bar, chords, vel=68 if k else 62)
        if k == 0:
            s.melody(mar, bar, m, vel=70, legato=1.0, accent=0)
        elif k == 1:
            s.melody(acc, bar, m, vel=72, legato=0.9)
        elif k == 2:
            s.melody(acc, bar, m, vel=74, legato=0.9)
            s.melody(mar, bar, m, vel=50, octave=-1, legato=1.0, accent=0)
        else:
            s.melody(acc, bar, m, vel=72, legato=0.9)
            s.melody(mar, bar, m, vel=52, octave=1, legato=1.0, accent=0)
    return s, 32 * 4


def task() -> tuple[Song, float]:
    """寫程式：C 大調 72 bpm。鋼琴分解和弦＋柔和的弦樂墊底，鐵片琴偶爾一句旋律；不搶注意力。24 小節"""
    s = Song(72, seed=37)
    pno = s.part(0, PIANO, vol=92, pan=58, rev=70)
    pad_ = s.part(1, SLOW_STR, vol=50, pan=70, rev=85)
    vib = s.part(2, VIBES, vol=74, pan=80, rev=75)
    cel = s.part(3, CELESTA, vol=66, pan=40, rev=80)
    A = ["Fmaj7", "Em7", "Dm7", "Cmaj7", "Fmaj7", "Em7", "Dm7", "Cmaj7"]
    m = "A4:1.5 C5:.5 E5:2  D5:1.5 B4:.5 G4:2  F4:1 A4:1 C5:1 D5:1  E5:3 r:1  A4:1.5 C5:.5 F5:2  E5:1 D5:1 B4:2  C5:1 A4:1 D5:1 B4:1  C5:3 r:1"

    def piano(bar, chords, vel=50):
        for i, sym in enumerate(chords):
            r, q, _ = chord(sym)
            b0 = (bar + i) * 4
            root = near(r, 43)
            s.note(pno, b0, 3.9, root, vel + 4)
            s.note(pno, b0, 3.9, root + 7, vel - 6)
            # 右手：慢慢往上再往下的分解和弦
            up = [near((r + iv) % 12, 62 + j * 3) for j, iv in enumerate(q[1:] + (12,))]
            seq = up + up[-2::-1] + up[:1]
            for k, p in enumerate(seq[:8]):
                s.note(pno, b0 + k * 0.5, 1.2, p, vel - (0 if k % 4 == 0 else 8))

    for k in range(3):
        bar = k * 8
        piano(bar, A, vel=48 if k != 1 else 44)
        if k >= 1:
            pad(s, pad_, bar, A, vel=36 if k == 1 else 32, center=64)
        if k == 1:
            s.melody(vib, bar, m, vel=58, legato=1.0)
        if k == 2:
            s.melody(cel, bar, m, vel=54, octave=1, legato=1.0)
    return s, 24 * 4


def clear() -> tuple[Song, float]:
    """過關：C 大調。木琴往上爬 → IV、V → 最後的 C 和弦一路往上揚，鐵琴閃一下到最高的 C。"""
    s = Song(120, seed=5)
    xyl = s.part(0, XYLO, vol=96, pan=70, rev=55)
    glk = s.part(1, GLOCK, vol=84, pan=84, rev=70)
    piz = s.part(2, PIZZ, vol=92, pan=44, rev=50)
    strn = s.part(3, STRINGS, vol=88, pan=56, rev=70)
    hrn = s.part(4, HORN, vol=72, pan=40, rev=65)
    # 旋律：往上的琶音 → F → G → 高音 C
    s.melody(xyl, 0, "G4:.25 C5:.25 E5:.25 G5:.25  F5:.25 A5:.25 C6:.5  G5:.25 B5:.25 D6:.5  C6:2", vel=92, legato=1.0)
    s.melody(glk, 0, "r:1 r:1 r:1 C6:2", vel=74, legato=1.0)
    # 最後一拍：鐵琴一顆一顆往上閃，停在最高的 C
    for k, n in enumerate(["E6", "G6", "C7"]):
        s.note(glk, 3.25 + k * 0.25, 2.5 - k * 0.25, pitch(n), 70 + k * 6)
    # 低音和和弦：C → F → G → C（越來越亮）
    for beat, sym in [(0, "C"), (1, "F"), (2, "G")]:
        r, q, _ = chord(sym)
        s.note(piz, beat, 0.4, near(r, 43), 80)
        for k, iv in enumerate(q):
            s.note(piz, beat + 0.5, 0.3, near((r + iv) % 12, 60 + k * 4), 66)
    # 終止和弦由低往高一個一個疊上去，弦樂和法國號漸強撐住
    final = ["C3", "C4", "E4", "G4", "C5", "E5", "G5"]
    for k, n in enumerate(final):
        s.note(strn, 3 + k * 0.06, 2.2 - k * 0.06, pitch(n), 70 + k * 4)
    for n in ["C4", "G4", "E5"]:
        s.note(hrn, 3, 2.1, pitch(n), 68)
    s.note(piz, 3, 0.6, pitch("C3"), 90)
    s.expr(strn, 0, 80)
    for k in range(9):
        s.expr(strn, 3 + k * 0.2, min(127, 80 + k * 6))
    s.expr(hrn, 0, 85)
    for k in range(9):
        s.expr(hrn, 3 + k * 0.2, min(127, 85 + k * 5))
    return s, 6


def bell() -> tuple[Song, float]:
    """上課鐘：學校鐘聲的第一段「噹噹噹噹」，小小聲、輕輕的（西敏寺鐘聲，1793 年的公共領域旋律），管鐘＋一點鋼片琴。"""
    s = Song(132, seed=7)
    tb = s.part(0, 14, vol=110, pan=64, rev=90)       # 管鐘
    cel = s.part(1, CELESTA, vol=60, pan=80, rev=80)
    phr = "E5:1 C5:1 D5:1 G4:3"   # 只要第一段，輕輕的
    s.melody(tb, 0, phr, vel=62, legato=1.6, accent=0)
    s.melody(cel, 0, phr, vel=34, octave=1, legato=1.2, accent=0)
    return s, 6


def battle() -> tuple[Song, float]:
    """出發冒險：小鼓和定音鼓滾奏越來越大聲 → 管弦樂重擊 → 小號衝鋒號角＋弦樂奔馳 → 停在明亮的 D 大和弦。"""
    s = Song(144, seed=9)
    dr = s.part(9, 0, vol=110, rev=40)                  # 打擊樂（GM 第 10 聲道）
    tim = s.part(0, 47, vol=112, pan=60, rev=55)        # 定音鼓
    brs = s.part(1, 61, vol=100, pan=50, rev=60)        # 銅管組
    tpt = s.part(2, 56, vol=108, pan=74, rev=60)        # 小號
    strn = s.part(3, STRINGS, vol=96, pan=40, rev=55)
    hit = s.part(4, 55, vol=96, pan=64, rev=60)         # 管弦樂重擊
    # 0–2 拍：滾奏漸強
    for k in range(16):
        s.note(dr, k * 0.125, 0.1, 38, 34 + k * 5)
    for k in range(8):
        s.note(tim, k * 0.25, 0.24, pitch("A2"), 50 + k * 8)
    # 第 2 拍：重擊！
    s.note(dr, 2, 0.5, 49, 120)
    s.note(dr, 2, 0.3, 36, 120)
    for n in ["D3", "A3", "D4", "F4", "A4"]:
        s.note(hit, 2, 0.6, pitch(n), 118)
    s.note(tim, 2, 0.5, pitch("D2"), 124)
    # 2–6 拍：弦樂奔馳（八分＋兩個十六分），定音鼓跟著
    for b in range(4):
        root = ["D3", "D3", "Bb2", "A2"][b]
        for off, d in [(0, 0.5), (0.5, 0.25), (0.75, 0.25)]:
            s.note(strn, 2 + b + off, d * 0.9, pitch(root), 96)
            s.note(strn, 2 + b + off, d * 0.9, pitch(root) + 12, 88)
        s.note(tim, 2 + b, 0.3, pitch(root) - 12 if b < 2 else pitch(root), 96)
        s.note(dr, 2 + b + 0.5, 0.2, 38, 70 + b * 8)
        s.note(dr, 2 + b, 0.2, 36, 100)
    # 小號衝鋒號角
    s.melody(tpt, 0, "r:2 D5:.5 r:.25 D5:.25 F5:.5 D5:.5 G5:.5 F5:.5 E5:.5 C#5:.5 D5:2.5", vel=104, legato=0.85)
    s.melody(brs, 0, "r:2 D4:.75 D4:.25 r:1 Bb3:1 A3:1 D4:2.5", vel=96, legato=0.9)
    s.melody(brs, 0, "r:2 A3:.75 A3:.25 r:1 F3:1 E3:1 F#4:2.5", vel=90, legato=0.9)
    # 第 6 拍：明亮的 D 大和弦＋鈸
    s.note(dr, 6, 1.5, 49, 118)
    s.note(dr, 6, 0.3, 36, 118)
    s.note(tim, 6, 0.3, pitch("D2"), 120)
    for n in ["D3", "A3", "D4", "F#4", "A4", "D5"]:
        s.note(strn, 6, 2.2, pitch(n), 104)
    s.note(tim, 6.5, 0.25, pitch("A2"), 100)
    s.note(tim, 6.75, 0.25, pitch("A2"), 100)
    s.note(tim, 7, 0.4, pitch("D2"), 124)
    s.note(dr, 7, 1.5, 49, 110)
    return s, 10


TRACKS = {"home": (home, True, 0.11), "town": (town, True, 0.11),
          "task": (task, True, 0.09), "clear": (clear, False, 0.14),
          "bell": (bell, False, 0.045), "battle": (battle, False, 0.16)}


def main() -> None:
    names = sys.argv[1:] or list(TRACKS)
    os.makedirs(GAME, exist_ok=True)
    for name in names:
        fn, loop, rms = TRACKS[name]
        song, beats = fn()
        a = finish(render(song, name, beats, loop), rms)
        path = os.path.join(GAME, f"{name}.ogg")
        write_ogg(path, a)
        sf.write(f"{WORK}/{name}.wav", a, SR)  # 試聽用
        print("wrote", name, round(len(a) / SR, 1), "s", flush=True)


if __name__ == "__main__":
    main()
