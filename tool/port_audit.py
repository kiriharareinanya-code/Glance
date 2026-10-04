"""Lyricify 移植完整性审计：把上游每个 .cs 映射到我们的 .dart，比对"有效代码行数"。

用途：证明"抄全了"，并揪出**抄薄了**的文件（ratio 明显偏低 = 可疑）。
运行：python tool/port_audit.py            （人读表格）
      python tool/port_audit.py --json     （给别的脚本用）
"""
from __future__ import annotations

import json
import os
import re
import sys

try:  # 控制台是 GBK 时中文会变乱码，强制 UTF-8 输出
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HELPER = r"C:\Users\81157\Documents\deepseek-harness\default-workspace\refs\Lyricify-Lyrics-Helper\Lyricify.Lyrics.Helper"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LYRICS = os.path.join(ROOT, "lib", "lyrics")


def code_lines(path: str) -> int:
    """有效代码行：去掉空行与整行注释（C# 用 //，Dart 也用 //）。"""
    n = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            t = line.strip()
            if not t or t.startswith("//") or t.startswith("///") or t.startswith("*") or t.startswith("/*"):
                continue
            n += 1
    return n


def snake(name: str) -> str:
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()


def upstream_files() -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(HELPER):
        dirnames[:] = [d for d in dirnames if d != "obj"]
        for fn in filenames:
            if fn.endswith(".cs"):
                out.append(os.path.relpath(os.path.join(dirpath, fn), HELPER).replace("\\", "/"))
    return sorted(out)


def map_to_dart(rel: str) -> str | None:
    """上游相对路径 → 我们的 Dart 相对路径（None = 没有对应文件）。"""
    name = rel.rsplit("/", 1)[-1][:-3]
    parts = rel.split("/")

    if parts[0] == "Decrypter":
        return f"decrypters/{snake(parts[1])}/{snake(name)}.dart"
    if parts[0] == "Generators":
        return f"generators/{snake(name)}.dart"
    if parts[0] == "Helpers":
        if parts[1] == "General":
            return f"helpers/general/{snake(name)}.dart"
        if parts[1] == "Optimization":
            return f"helpers/optimization/{snake(name)}.dart"
        if parts[1] == "Types":
            return f"helpers/types/{snake(name)}.dart"
        if name == "TypeHelper":
            return "helpers/types/type_helper.dart"
        return f"helpers/{snake(name)}.dart"
    if parts[0] == "Parsers":
        if parts[1] == "Models":
            return f"parsers/models/{snake(name)}.dart"
        return f"parsers/{snake(name)}.dart"
    if parts[0] == "Providers":
        if parts[1] == "Web":
            if len(parts) > 3:
                return f"providers/web/{parts[2].lower()}/{snake(name)}.dart"
            return f"providers/web/{snake(name)}.dart"
        return f"providers/{snake(name)}.dart"
    if parts[0] == "Searchers":
        if parts[1] == "Helpers":
            if parts[2] == "MatchHelpers":
                return f"searchers/helpers/match_helpers/{snake(name)}.dart"
            return f"searchers/helpers/{snake(name)}.dart"
        return f"searchers/{snake(name)}.dart"
    if parts[0] == "Models":
        return f"models/{snake(name)}.dart"
    return None


# 上游刻意合并进同文件的（见 docs/lyricify-port.md 第 7 节的命名差异对账表）
MERGED = {
    "Helpers/Types/LyricsTypes.cs": ["helpers/types/lyrics_type_detector.dart"],
    "Models/ILineInfo.cs": ["models/line_info.dart"],
    "Models/LineInfo.cs": ["models/line_info.dart"],
    "Models/ISyllableInfo.cs": ["models/syllable_info.dart"],
    "Models/SyllableInfo.cs": ["models/syllable_info.dart"],
    "Models/SyncTypes.cs": ["models/lyrics_types.dart"],
    "Models/LyricsTypes.cs": ["models/lyrics_types.dart"],
    "Models/ITrackMetadata.cs": ["models/track_metadata.dart"],
    "Models/TrackMetadata.cs": ["models/track_metadata.dart"],
    "Decrypter/Qrc/DESHelper.cs": ["decrypters/qrc/des_helper.dart"],
    "Providers/Web/BaseApi.cs": ["providers/web/base_api.dart"],
}

# 上游用全大写缩写词、我们按词拆开（AppleMusic / LRCLIB / SodaMusic / QQMusic / MusixMatch）
SPECIAL = {
    "Searchers/AppleMusicSearcher.cs": "searchers/applemusic_searcher.dart",
    "Searchers/AppleMusicSearchResult.cs": "searchers/applemusic_search_result.dart",
    "Searchers/LRCLIBSearcher.cs": "searchers/lrclib_searcher.dart",
    "Searchers/LRCLIBSearchResult.cs": "searchers/lrclib_search_result.dart",
    "Searchers/SodaMusicSearcher.cs": "searchers/sodamusic_searcher.dart",
    "Searchers/SodaMusicSearchResult.cs": "searchers/sodamusic_search_result.dart",
    "Searchers/QQMusicSearcher.cs": "searchers/qqmusic_searcher.dart",
    "Searchers/QQMusicSearchResult.cs": "searchers/qqmusic_search_result.dart",
    "Searchers/MusixmatchSearcher.cs": "searchers/musixmatch_searcher.dart",
    "Searchers/MusixmatchSearchResult.cs": "searchers/musixmatch_search_result.dart",
    "Providers/Web/AppleMusic/Api.cs": "providers/web/applemusic/api.dart",
    "Providers/Web/AppleMusic/Response.cs": "providers/web/applemusic/response.dart",
    "Providers/Web/LRCLIB/Api.cs": "providers/web/lrclib/api.dart",
    "Providers/web/LRCLIB/Response.cs": "providers/web/lrclib/response.dart",
    "Providers/Web/SodaMusic/Api.cs": "providers/web/sodamusic/api.dart",
    "Providers/Web/SodaMusic/Response.cs": "providers/web/sodamusic/response.dart",
    "Providers/Web/QQMusic/Api.cs": "providers/web/qqmusic/api.dart",
    "Providers/Web/QQMusic/Response.cs": "providers/web/qqmusic/response.dart",
    "Providers/Web/MusixMatch/Api.cs": "providers/web/musixmatch/api.dart",
    "Providers/Web/MusixMatch/ApiOptions.cs": "providers/web/musixmatch/api_options.dart",
    "Providers/Web/MusixMatch/Response.cs": "providers/web/musixmatch/response.dart",
    "Providers/IProvider.cs": "providers/i_provider.dart",
    "Providers/IProviderResult.cs": "providers/i_provider_result.dart",
    "Providers/QQMusicProviderResult.cs": "providers/qqmusic_provider_result.dart",
}


def main() -> int:
    rows = []
    for rel in upstream_files():
        cs = os.path.join(HELPER, rel.replace("/", os.sep))
        target = SPECIAL.get(rel) or map_to_dart(rel)
        targets = MERGED.get(rel, [target] if target else [])
        if not targets:
            rows.append({"cs": rel, "cs_lines": code_lines(cs), "dart": None, "dart_lines": 0})
            continue
        first = os.path.join(LYRICS, targets[0].replace("/", os.sep))
        if not os.path.exists(first):
            rows.append({"cs": rel, "cs_lines": code_lines(cs), "dart": targets[0], "dart_lines": -1})
            continue
        dl = sum(code_lines(os.path.join(LYRICS, t.replace("/", os.sep))) for t in targets if os.path.exists(os.path.join(LYRICS, t.replace("/", os.sep))))
        rows.append({
            "cs": rel,
            "cs_lines": code_lines(cs),
            "dart": targets[0] + (f" (+{len(targets)-1})" if len(targets) > 1 else ""),
            "dart_lines": dl,
            "ratio": round(dl / code_lines(cs), 2) if code_lines(cs) else 0,
        })

    if "--json" in sys.argv:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0

    missing = [r for r in rows if r["dart_lines"] == -1]
    mapped = [r for r in rows if r["dart_lines"] >= 0]
    thin = sorted((r for r in mapped if r.get("ratio", 1) < 0.55), key=lambda r: r["ratio"])
    thick = sorted((r for r in mapped if r.get("ratio", 0) > 1.6), key=lambda r: -r["ratio"])

    print(f"上游 .cs 合计 {len(rows)} 个（不含 obj/），映射到现有 Dart 文件 {len(mapped)} 个")
    print(f"总代码行：上游 {sum(r['cs_lines'] for r in rows)} → 我们 {sum(r['dart_lines'] for r in mapped if r['dart_lines'] > 0)}")
    if missing:
        print(f"\n!! 缺文件（{len(missing)}）：")
        for r in missing:
            print(f"  {r['cs']:<58} -> {r['dart']}")
    if thin:
        print(f"\n== 抄得偏薄，ratio < 0.55（{len(thin)}）：")
        for r in thin:
            print(f"  {r['cs']:<58} {r['cs_lines']:>5} -> {r['dart_lines']:>5}  ({r['ratio']})")
    if thick:
        print(f"\n== 抄得偏厚（>1.6，通常是加了宿主胶水，正常）：")
        for r in thick:
            print(f"  {r['cs']:<58} {r['cs_lines']:>5} -> {r['dart_lines']:>5}  ({r['ratio']})")
    if not missing and not thin:
        print("\n全部文件都有对应实现，且没有明显抄薄的文件。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())