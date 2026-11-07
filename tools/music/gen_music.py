"""用 Meta MusicGen 生成遊戲背景音樂，做成可以無縫循環的 .ogg。

環境：D:/ai/musicgen（python -m venv；torch cu126、transformers、soundfile）
用法：D:/ai/musicgen/Scripts/python tools/music/gen_music.py [曲名 ...] [--model medium] [--takes 2]
輸出：D:/ai/musicgen_out/<曲名>_<n>.ogg（候選，給人聽）；第 1 個候選複製到 audio/music/<曲名>.ogg

模型權重授權：CC-BY-NC 4.0（非商業用途），製作名單要註明 MusicGen by Meta。
"""
import argparse
import os
import shutil
import sys

os.environ.setdefault("HF_HOME", "D:/ai/hf")

import numpy as np
import soundfile as sf
import torch
from transformers import AutoProcessor, MusicgenForConditionalGeneration

# 曲名: (提示詞, 秒數, 是否循環)
TRACKS = {
    "home": ("cozy storybook forest cottage background music, gentle fingerpicked acoustic guitar, "
             "soft glockenspiel and light wooden flute, warm, peaceful and relaxing, slow 80 bpm, "
             "children's picture book, no drums, instrumental", 30, True),
    "town": ("cheerful small village market music, ukulele and soft accordion, light pizzicato strings, "
             "gentle hand percussion, bright and friendly, 100 bpm, cozy game soundtrack, instrumental", 30, True),
    "task": ("calm focused lofi music for studying, soft felt piano, warm pads, gentle brushed beat, "
             "relaxing cozy game, 72 bpm, instrumental", 30, True),
    "clear": ("short happy celebration jingle, xylophone and bells, cheerful little fanfare, "
              "cozy children's game, instrumental", 5, False),
}

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = "D:/ai/musicgen_out"
GAME = os.path.join(ROOT, "audio", "music")


def make_loop(a: np.ndarray, sr: int, fade_s: float = 3.0) -> np.ndarray:
    """尾巴交叉淡入到開頭：播完接回開頭聽不出接縫。"""
    f = int(sr * fade_s)
    body = a[: len(a) - f].copy()
    t = np.linspace(0.0, 1.0, f)
    fin = np.sin(t * np.pi / 2) ** 2
    body[:f] = a[:f] * fin + a[len(a) - f:] * (1.0 - fin)
    return body


def finish(a: np.ndarray, sr: int, loop: bool) -> np.ndarray:
    a = a - a.mean()
    if loop:
        a = make_loop(a, sr)
    else:
        n = int(sr * 0.8)
        a[-n:] *= np.linspace(1.0, 0.0, n) ** 2
    # 音量：RMS 對齊，峰值不超過 -1 dB
    rms = np.sqrt(np.mean(a ** 2)) + 1e-9
    a = a * (0.12 / rms)
    peak = np.abs(a).max()
    if peak > 0.89:
        a = a * (0.89 / peak)
    return a.astype(np.float32)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--model", default="medium")
    ap.add_argument("--takes", type=int, default=2)
    args = ap.parse_args()
    names = args.names or list(TRACKS)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(GAME, exist_ok=True)
    mid = f"facebook/musicgen-{args.model}"
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if dev == "cuda" else torch.float32
    print("loading", mid, dev, flush=True)
    proc = AutoProcessor.from_pretrained(mid)
    model = MusicgenForConditionalGeneration.from_pretrained(mid, torch_dtype=dtype).to(dev)
    sr = model.config.audio_encoder.sampling_rate
    for name in names:
        prompt, secs, loop = TRACKS[name]
        extra = 3 if loop else 0
        tokens = int((secs + extra) * 50)
        for k in range(1, args.takes + 1):
            torch.manual_seed(1000 + k * 17 + sum(map(ord, name)))
            inp = proc(text=[prompt], padding=True, return_tensors="pt").to(dev)
            with torch.no_grad():
                out = model.generate(**inp, do_sample=True, guidance_scale=3.0, max_new_tokens=tokens)
            a = out[0, 0].float().cpu().numpy()
            a = finish(a, sr, loop)
            path = f"{OUT}/{name}_{k}.ogg"
            sf.write(path, a, sr, format="OGG", subtype="VORBIS")
            print("wrote", path, round(len(a) / sr, 1), "s", flush=True)
            if k == 1:
                shutil.copy(path, os.path.join(GAME, f"{name}.ogg"))


if __name__ == "__main__":
    sys.exit(main())
