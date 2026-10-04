"""把上游 .cs 的 XML 文档注释还原到 Dart 移植文件里。

背景：最初的移植流水线把上游的中文 `///` 注释剥掉了，只留下空的 `///`，
等于丢了上游对每个方法的说明（docs/lyricify-port.md 第 4 节要求"注释全部保留"）。

做法（按**成员名**对齐，不按行号——行号在 C#→Dart 转换后必然错位）：
  1. 扫上游：每个 `///` 块 → (紧随其后的成员名, 注释正文)
  2. 扫我们这边：每个**内容为空**的 `///` 块 → (紧随其后的成员名)
  3. 名字对得上就把上游正文写回去；**对不上一律不动**（宁可留空也不瞎猜）

XML → Dart 注释的转换：`<summary>` 丢掉标签留正文，`<param name="x">` → `@param x`，
`<returns>` → `@returns`，其余尖括号标签去掉。

用法：
    python tool/restore_doc_comments.py --dry-run     # 只报告，不写盘
    python tool/restore_doc_comments.py --apply       # 写盘
    python tool/restore_doc_comments.py --dry-run -v  # 顺带打印将要写入的内容
    python tool/restore_doc_comments.py --apply --keep-empty
                                                      # 保留对不上的空 ///（默认会删掉）

对不上上游的空 `///` 默认**删掉**：空文档注释在 dartdoc 里是个空条目，
比没有更糟。留着的话宁可一个不留。
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

HELPER = port_audit.HELPER
LYRICS = port_audit.LYRICS

# C# 声明行 → 成员名
CS_DECL = [
    re.compile(r'^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:readonly\s+)?'
               r'(?:const\s+)?(?:async\s+)?(?:partial\s+)?(?:class|enum|interface|record(?:\s+class)?|struct)\s+(\w+)'),
    re.compile(r'^\s*(?:public|private|protected|internal)\s+(?:static\s+)?(?:readonly\s+)?'
               r'(?:const\s+)?(?:async\s+)?(?:virtual\s+|override\s+|new\s+)*'
               r'[\w\.<>\[\],\?:\s]+?\s+(\w+)\s*(?:\(|=>|\{|=)'),
    re.compile(r'^\s*(?:public|private|protected|internal)\s+[\w\.<>\[\],\?:\s]+?\s+(\w+)\s*\{\s*(?:get|set)'),
]
# Dart 声明行 → 成员名
DART_DECL = [
    re.compile(r'^\s*(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+|mixin\s+)*'
               r'(?:class|enum|extension|mixin)\s+(\w+)'),
    re.compile(r'^\s*(?:static\s+|final\s+|const\s+|late\s+|covariant\s+)*'
               r'(?:[\w\.<>\[\],\?:\s]+?)\s+(?:get\s+|set\s+)?(\w+)\s*(?:\(|=>|\{|=|;)'),
]
SKIP_NAMES = {"if", "for", "while", "switch", "return", "await", "try", "catch",
              "finally", "else", "do", "break", "continue", "extends", "implements",
              "with", "on", "library", "dart", "assert", "super", "this"}


def member_name(line: str, decls: list[re.Pattern]) -> str | None:
    for rx in decls:
        m = rx.match(line)
        if m:
            n = m.group(1)
            return None if n in SKIP_NAMES else n
    return None


def blocks(lines: list[str], decls: list[re.Pattern]):
    """产出 (块起止行号, 成员名, 块内容行列表)。块=连续的 /// 行。"""
    i = 0
    while i < len(lines):
        if lines[i].lstrip().startswith("///"):
            j = i
            while j < len(lines) and lines[j].lstrip().startswith("///"):
                j += 1
            k = j
            while k < len(lines) and not lines[k].strip():
                k += 1
            name = member_name(lines[k].strip(), decls) if k < len(lines) else None
            yield i, j, name, lines[i:j]
            i = j
        else:
            i += 1


def xml_to_dart(content: list[str]) -> list[str] | None:
    """把上游 XML 文档转成 Dart 的 /// 行；正文为空则返回 None。"""
    out: list[str] = []
    buf = ""

    def flush():
        nonlocal buf
        for piece in (p.strip() for p in buf.split("\n")):
            if piece:
                out.append(piece)
        buf = ""

    for raw in content:
        t = raw.strip()
        t = t[3:].strip()                      # 去掉 ///
        t = re.sub(r'^<summary>\s*', '', t)  # 开标签
        t = re.sub(r'\s*</summary>$', '', t)  # 闭标签
        m = re.match(r'^<param name="([^"]+)">\s*(.*?)\s*(?:</param>)?$', t)
        if m:
            flush()
            # 上游很多 `<param name="id">` 是空的，这种注解写了等于没写，不要。
            if m.group(2):
                out.append(f"@param {m.group(1)} {m.group(2)}".strip())
            continue
        m = re.match(r'^<(returns|remarks|example|exception)(\s[^>]*)?>\s*(.*?)'
                     r'\s*(?:</\1>)?$', t)
        if m:
            flush()
            body = m.group(3)
            if body:
                out.append(f"@{m.group(1)} {body}".strip())
            elif m.group(1) == "returns":
                continue          # 空 @returns 同理，丢掉
            else:
                out.append(f"@{m.group(1)}")
            continue
        t = re.sub(r'</?[a-zA-Z][^>]*>', '', t)   # 其它标签去标签留正文
        t = t.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
        if not t and out:
            flush()
            continue
        buf += ("\n" if buf else "") + t
    flush()
    if not out:
        return None
    return ["  /// " + o if o else "  ///" for o in out]


def main() -> int:
    apply = "--apply" in sys.argv
    verbose = "-v" in sys.argv
    keep_empty = "--keep-empty" in sys.argv
    total_files = filled = drops = total_blocks = 0

    for rel in port_audit.upstream_files():
        target = port_audit.SPECIAL.get(rel) or port_audit.map_to_dart(rel)
        if not target:
            continue
        dart_path = os.path.join(LYRICS, target.replace("/", os.sep))
        if not os.path.exists(dart_path):
            continue
        cs_path = os.path.join(HELPER, rel.replace("/", os.sep))
        cs_lines = io.open(cs_path, encoding="utf-8", errors="replace").read().split("\n")
        dart_lines = io.open(dart_path, encoding="utf-8", errors="replace").read().split("\n")

        # 上游：名字（去掉下划线、统一小写）→ 注释
        upstream: dict[str, list[str]] = {}
        for _, _, name, content in blocks(cs_lines, CS_DECL):
            if not name:
                continue
            doc = xml_to_dart(content)
            if doc:
                upstream.setdefault(name.lower(), doc)

        # 我们这边：空 /// 块
        edits: list[tuple[int, int, list[str], str]] = []
        drop: list[tuple[int, int]] = []
        for i, j, name, content in blocks(dart_lines, DART_DECL):
            if not name:
                continue
            if any(c.strip() not in ("///", "////") for c in content):
                continue        # 已有内容，不碰
            doc = upstream.get(name.lower())
            if doc:
                edits.append((i, j, doc, name))
            else:
                drop.append((i, j))

        if not edits and not drop:
            continue
        total_files += 1
        total_blocks += len(edits)
        filled += len(edits)
        drops += len(drop)
        print(f"{target}: 还原 {len(edits)} 处" + (f"，删除空注释 {len(drop)} 处" if drop else ""))
        for i, j, doc, name in edits:
            if verbose:
                print(f"    L{i+1} {name} ← " + doc[0].strip())
                for d in doc[1:]:
                    print("         " + d.strip())

        if apply:
            # 关键：edits 和 drop **必须合并成一次倒序应用**。
            # 两次循环看起来都各自倒序、都没问题，但 edits 会改变行数，
            # 于是 drop 里那些"改动前算好的行号"全部失效，删到的是别处的代码
            # （曾经把某个方法的 return 删掉，编译器报"非空 double 没有返回值"）。
            # 合并成一份 (start, end, replacement|None) 倒序处理即可。
            ops: list[tuple[int, int, list[str] | None]] = [
                (i, j, doc) for i, j, doc, _ in edits
            ]
            if not keep_empty:
                ops += [(i, j, None) for i, j in drop]
            for i, j, repl in sorted(ops, reverse=True):
                dart_lines[i:j] = repl if repl is not None else []
            io.open(dart_path, "w", encoding="utf-8", newline="\n").write("\n".join(dart_lines))

    print(f"\n共 {total_files} 个文件、{total_blocks} 处注释还原"
          f"、{drops} 处空注释删除"
          f"{'（已写盘）' if apply else '（dry-run，未写盘）'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())