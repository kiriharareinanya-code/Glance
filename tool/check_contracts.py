"""核对 docs/lyricify-port.md 里写死的"契约"，防止后来者悄悄破坏。

检查项：
  1. §0.2 每个移植文件顶部必须有出处注释 `// Ported from Lyricify.Lyrics.Helper/...`
  2. §4.18 lib/lyrics/** 不得 import Flutter（package:flutter/*）
  3. §4.18 lib/lyrics/** 只能 import 允许的 dart:* 与 package:http、package:xml
  4. §3.6 StringHelper / MathHelper 的关键静态方法必须存在且没被改名
  5. LICENSE / NOTICE 必须在（Apache-2.0 的 §4(a)/(b) 义务）

用法：python tool/check_contracts.py        （有问题返回非 0）
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import port_audit  # noqa: E402

LYRICS = port_audit.LYRICS

# 非移植文件（宿主胶水 / 契约文件），不要求出处注释
HOST_FILES = {
    "LICENSE", "NOTICE",
    "lyrics_log.dart", "json_utils.dart", "engine.dart", "engine_sources.dart",
    "http/lyrics_http.dart",
}
# 允许的 import（按前缀匹配，允许 `package:x/y.dart` 这样的深层导入）
ALLOWED_DART = ("dart:core", "dart:async", "dart:convert", "dart:math", "dart:io",
                "dart:typed_data", "dart:collection")
ALLOWED_PKG = ("package:http", "package:xml", "package:crypto", "package:pointycastle")
# §3.6 点名不许改的方法
REQUIRED = {
    "helpers/general/string_helper.dart": [
        "isSame", "isSameWhiteSpace", "isSameTrim", "computeTextSame",
        "removeDuoSpaces", "removeTripleSpaces", "fixCommaAfterSpace",
        "removeDuoBackslashN", "removeBackslashR", "formatTimeMsToTimestampString",
        "getMillisecondsFromString", "toUpperFirst", "between", "reverse", "remove",
        "removeControlChars", "fixIWords", "removeFrontBackBrackets",
        "canStartNewLine", "containsAny", "isNumber", "hasCJK", "isCJK",
        "optimizeCJK", "isChinese", "hasChinese", "chinesePercentage",
        "traditionalChineseConfidence", "isEmoji", "containsEmoji",
    ],
    "helpers/general/math_helper.dart": ["min", "max", "greaterThanZero",
                                         "greaterThan", "isBetween"],
    "helpers/general/chinese_helper.dart": ["s2T", "t2S", "toTC", "toSC", "isTraditional"],
}

IMPORT_LINE = re.compile(r"^\s*(?:import|export)\s+(['\"])([^'\"]+)\1")


def dart_files() -> list[str]:
    out = []
    for dirpath, _dirs, files in os.walk(LYRICS):
        for fn in files:
            if fn.endswith(".dart"):
                out.append(os.path.relpath(os.path.join(dirpath, fn), LYRICS).replace("\\", "/"))
    return sorted(out)


def main() -> int:
    problems: list[str] = []
    files = dart_files()

    for rel in files:
        path = os.path.join(LYRICS, rel.replace("/", os.sep))
        src = io.open(path, encoding="utf-8", errors="replace").read()
        lines = src.split("\n")

        # 1) 出处注释
        if rel not in HOST_FILES and "Ported from Lyricify.Lyrics.Helper/" not in "\n".join(lines[:6]):
            problems.append(f"[出处] {rel}: 顶部 6 行内没有 `// Ported from Lyricify.Lyrics.Helper/...`")

        # 2) 不得 import Flutter
        for ln in lines:
            m = IMPORT_LINE.match(ln)
            if not m:
                continue
            uri = m.group(2)
            if uri.startswith("package:flutter/"):
                problems.append(f"[依赖] {rel}: 禁止 import Flutter（{uri}）")
            elif uri.startswith("dart:") and not uri.startswith(ALLOWED_DART):
                problems.append(f"[依赖] {rel}: dart: 库不在允许清单（{uri}）")
            elif uri.startswith("package:") and not uri.startswith(ALLOWED_PKG):
                problems.append(f"[依赖] {rel}: 第三方包不在允许清单（{uri}）")

    # 4) 关键静态方法必须还在
    for rel, names in REQUIRED.items():
        path = os.path.join(LYRICS, rel.replace("/", os.sep))
        if not os.path.exists(path):
            problems.append(f"[契约] {rel}: 文件不存在")
            continue
        src = io.open(path, encoding="utf-8", errors="replace").read()
        for n in names:
            if not re.search(rf"\bstatic\s+[\w<>,\[\]?\s]*\b{n}\s*\(", src):
                problems.append(f"[契约] {rel}: 缺少或改名了 `{n}`")

    # 5) Apache-2.0 义务
    for f in ("LICENSE", "NOTICE"):
        if not os.path.exists(os.path.join(LYRICS, f)):
            problems.append(f"[许可] lib/lyrics/{f} 缺失")
    lic = os.path.join(LYRICS, "LICENSE")
    if os.path.exists(lic):
        head = io.open(lic, encoding="utf-8", errors="replace").read(400)
        if "Apache License" not in head:
            problems.append("[许可] lib/lyrics/LICENSE 不是 Apache-2.0 全文")

    if problems:
        print(f"契约检查未通过（{len(problems)} 项）：")
        for p in problems:
            print("  " + p)
        return 1
    print(f"契约检查通过：{len(files)} 个 Dart 文件，出处注释 / 依赖白名单 / "
          f"关键方法签名 / LICENSE+NOTICE 全部合规。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())