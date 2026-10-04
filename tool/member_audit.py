"""成员级保真审计：把上游 .cs 的成员名与我们的 .dart 成员名逐一对比。

目的：抓"抄漏了某个方法/字段"的静默缺口（行数对比看不出来）。
只比**名字**，不比实现——实现由各worker 的单测保证。

规则：
  C# 成员：public/private/protected/internal 的属性、方法、字段、构造函数；
  Dart 成员：顶层/类内的函数、getter/setter、字段、构造、静态成员；
  名字按 lowerCamel 比较（C# PascalCase 与 Dart lowerCamelCase 是同名的两种写法），
  嵌套类型（class/enum/interface/record）也单列。

运行：python tool/member_audit.py           （人读，只报可疑项）
      python tool/member_audit.py --all     （全量，含已确认对齐的项）
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
from port_audit import LYRICS, code_lines, map_to_dart, snake, upstream_files  # noqa: E402
import port_audit  # noqa: E402

HELPER = port_audit.HELPER

# 上游成员的书写形态
CS_MEMBER = [
    re.compile(r'^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:readonly\s+)?'
               r'(?:async\s+)?(?:virtual\s+|override\s+|sealed\s+|partial\s+)*'
               r'(?P<type>[\w\.<>\[\],\?:\s]+?)\s+(?P<name>\w+)\s*(?:\(|=>|\{|=)'),
    re.compile(r'^\s*(?:public|private|protected|internal)\s+(?P<type>[\w\.<>\[\],\?:\s]+?)\s+'
               r'(?P<name>\w+)\s*\{\s*(?:get|set)'),
    re.compile(r'^\s*(?:public|private|protected|internal)\s+(?:static\s+)?'
               r'(?:partial\s+)?(?:class|enum|interface|record(?: class)?|struct)\s+(?P<name>\w+)'),
]
# 我们这边：字段 / getter-setter / 方法 / 构造 / 类
DART_MEMBER = [
    re.compile(r'^\s*(?:static\s+|final\s+|const\s+|late\s+)*(?:[\w\.<>\[\],\?:\s]+?)\s+'
               r'(?:get\s+|set\s+)?(?P<name>\w+)\s*(?:\(|=>|\{|=|;)'),
]
# 类型声明要单独一条，否则 `class Foo extends Bar {` 会被当成"名字 = Bar"
DART_TYPE_DECL = re.compile(
    r'^\s*(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+|mixin\s+)*'
    r'(?:class|enum|extension|mixin)\s+(?P<name>\w+)')
# 只在这些修饰词后当作"成员声明"，避免把普通语句算进去
CS_MOD = re.compile(r'\b(public|private|protected|internal)\b')
DART_KEYWORDS = {
    'if', 'for', 'while', 'switch', 'return', 'assert', 'await', 'yield',
    'super', 'this', 'try', 'catch', 'finally', 'do', 'else', 'break', 'continue',
}
# C# 的 I 前缀接口，按契约被映射成 Dart 抽象类（名字去 I），不算缺失
CS_INTERFACE = re.compile(r'^[A-Z]I[A-Z]')
# 枚举成员：`LRC,` / `LRC = 1,` / Dart 的 `perfect(100),`（带构造参数）
# 末位成员在 Dart 里以 `;` 收尾，所以 `;` 也算终止符。
ENUM_ITEM = re.compile(r'^\s*(?P<name>[A-Za-z_]\w*)\s*(?:\([^()]*\))?\s*(?:=\s*[^,]+)?[,;]?\s*$')


def norm(name: str) -> str:
    """比较用的名字：去下划线、统一小写。

    分隔符也要去掉，否则上游 `Size_128MP3` 永远匹配不上 Dart 的 `size128mp3`
    ——这类全是同义不同名，不是漏抄。
    """
    return re.sub(r"[^a-z0-9]", "", name.lower())


def expand(names: set[str]) -> set[str]:
    """补上单/复数变体。

    上游 C# 的 JSON 字段是单数（`TaskType`），Dart 侧落成列表（`taskTypes`），
    这是命名选择而不是漏抄，别把它报成缺失。
    """
    out = set(names)
    for n in names:
        if n.endswith("s") and len(n) > 1:
            out.add(n[:-1])
    return out


def enum_members(path: str) -> set[str]:
    """扫出所有 enum 的成员名（上游/Dart 的枚举成员都不带类型前缀，正则抓不到）。"""
    out: set[str] = set()
    with io.open(path, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    depth = 0
    for raw in lines:
        line = raw.strip()
        if re.match(r'^(?:public\s+|internal\s+)?(?:static\s+)?enum\s+\w+', line) or \
           re.match(r'^(?:[\w<>,\[\]?\s]+?)\s+enum\s+\w+', line):
            depth = 1
            continue
        if depth:
            if line.startswith("}"):
                depth = 0
                continue
            m = ENUM_ITEM.match(line)
            if m and m.group("name") not in DART_KEYWORDS:
                out.add(norm(m.group("name")))
    return out


def members(path: str, lang: str) -> set[str]:
    out: set[str] = set()
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("//"):
                continue
            if lang == "cs":
                if not CS_MOD.search(line):
                    continue
                for rx in CS_MEMBER:
                    m = rx.match(line)
                    if m:
                        n = m.group("name")
                        if CS_INTERFACE.match(n):
                            break
                        out.add(norm(n))
                        break
            else:
                # 先判类型声明：否则 `class Foo extends Bar {` 会被通用正则
                # 匹配成"类型=class、名字=Bar"。
                m = DART_TYPE_DECL.match(line)
                if m:
                    out.add(norm(m.group("name")))
                    continue
                for rx in DART_MEMBER:
                    m = rx.match(line)
                    if not m:
                        continue
                    name = m.group("name")
                    if name in DART_KEYWORDS or name in {"dart", "library"}:
                        break
                    if name in {"extends", "implements", "with", "on"}:
                        continue
                    out.add(norm(name))
                    break
    return out


def main() -> int:
    show_all = "--all" in sys.argv
    rows = []
    for rel in upstream_files():
        target = port_audit.SPECIAL.get(rel) or map_to_dart(rel)
        targets = port_audit.MERGED.get(rel, [target] if target else [])
        if not targets:
            continue
        dart_paths = [os.path.join(LYRICS, t.replace("/", os.sep)) for t in targets]
        dart_paths = [p for p in dart_paths if os.path.exists(p)]
        if not dart_paths:
            continue
        cs_members = members(os.path.join(HELPER, rel.replace("/", os.sep)), "cs")
        cs_members |= enum_members(os.path.join(HELPER, rel.replace("/", os.sep)))
        dart_members: set[str] = set()
        for p in dart_paths:
            dart_members |= members(p, "dart")
            dart_members |= enum_members(p)
        missing = sorted(expand(cs_members) - expand(dart_members))
        if missing and (show_all or len(missing) >= 1):
            rows.append((rel, targets[0], missing))

    for rel, dart, missing in rows:
        print(f"{rel}\n    -> {dart}\n    缺: {', '.join(missing)}")
    print(f"\n共 {len(rows)} 个文件有疑似缺失成员。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())