"""从上游 ArtistHelper.cs 抽出 ArtistNamePairs，生成 Dart 字面量列表。

用法：python tool/gen_artist_pairs.py            （打印生成的 Dart 片段）
      python tool/gen_artist_pairs.py --apply    （直接改写 artist_helper.dart 里的空列表）

上游格式：`new("spotifyId", "Name", "ChineseName"),`
Dart 里对应 `ArtistNamePair('spotifyId', 'Name', 'ChineseName'),`
"""
from __future__ import annotations

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

CS = r"C:\Users\81157\Documents\deepseek-harness\default-workspace\refs\Lyricify-Lyrics-Helper\Lyricify.Lyrics.Helper\Searchers\Helpers\ArtistHelper.cs"
DART = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "lib", "lyrics", "searchers", "helpers", "artist_helper.dart")

# new("a", "b", "c")  —— 字符串里可能含 \" ，用非贪婪匹配 + 转义感知
ENTRY = re.compile(r'new\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)')

BLOCK_START = "static final List<ArtistNamePair> artistNamePairs = <ArtistNamePair>[\n"
BLOCK_END = "  ];\n"


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def dart_str(s: str) -> str:
    return s.replace("\\", "\\\\").replace("$", r"\$").replace("'", r"\'")


def build() -> list[str]:
    with io.open(CS, encoding="utf-8") as f:
        text = f.read()
    # 只取 ArtistNamePairs = new() { ... } 这一段，避免误抓别的 new(
    start = text.index("ArtistNamePairs")
    end = text.index("};", start)
    body = text[start:end]
    out = []
    for m in ENTRY.finditer(body):
        spotify_id, name, cn = (unescape(g) for g in m.groups())
        out.append(f"    ArtistNamePair('{dart_str(spotify_id)}', '{dart_str(name)}', '{dart_str(cn)}'),")
    return out


def main() -> int:
    entries = build()
    block = BLOCK_START + "\n".join(entries) + "\n" + BLOCK_END
    if "--apply" not in sys.argv:
        print(block)
        print(f"// 共 {len(entries)} 条", file=sys.stderr)
        return 0

    with io.open(DART, encoding="utf-8") as f:
        src = f.read()
    i = src.index(BLOCK_START)
    j = src.index(BLOCK_END, i) + len(BLOCK_END)
    src = src[:i] + block + src[j:]
    with io.open(DART, "w", encoding="utf-8", newline="\n") as f:
        f.write(src)
    print(f"已写入 {len(entries)} 条到 {DART}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())