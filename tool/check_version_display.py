"""校验 `app_version.dart` 里的显示串与 `pubspec.yaml` 的版本号一致。

## 为什么需要这个脚本

`kVersionDisplay` 是**硬编码的常量**（"Forst-0.2.130"），而真实来源
`pubspec.yaml` 的 `version:`（"0.2.0+133"）在发版时是会变的。两处各写各的，
于是每发一次版就漂一次：

- 改 pubspec → 编译 → 发布，exe 的文件属性是新的
- 但「关于」页显示的还是上一个数字

这个 bug 实际发生过：pubspec 已经是 0.2.0+132 / 133，面板里显示的仍然是
Forst-0.2.130。**不是忘了改，而是根本没人会记得去改第二个地方。**

所以把它变成一条能跑的检查：发版跑一遍，不一致就退出码非 0。

## 什么时候跑

    python tool/check_version_display.py

接进 CI 的话放在 build 之前；本地发版流程里手动跑一次也行。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
APP_VERSION = ROOT / "lib" / "core" / "app_version.dart"

# pubspec 的 version: 0.2.0+133 -> (0, 2, 0, 133)
PUB_RE = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.M)

# app_version.dart 的 kVersionDisplay = 'Forst-0.2.133'
DISP_RE = re.compile(r"""kVersionDisplay\s*=\s*['"]([^'"]+)['"]""")


def main() -> int:
    pub_text = PUBSPEC.read_text(encoding="utf-8")
    disp_text = APP_VERSION.read_text(encoding="utf-8")

    m = PUB_RE.search(pub_text)
    if not m:
        print("✗ 没能从 pubspec.yaml 解析出版本号")
        print("  期望形如： version: 0.2.0+133")
        return 1
    major, minor, patch, build = m.groups()

    d = DISP_RE.search(disp_text)
    if not d:
        print("✗ 没能从 app_version.dart 解析出 kVersionDisplay")
        return 1
    display = d.group(1)

    # 显示串的小版本号用「次版本 + build」，也就是 0.2.133 / 0.2.130
    want = f"Forst-{major}.{minor}.{build}"
    if display == want:
        print(f"✓ 版本显示串一致：{display}（对应 pubspec {major}.{minor}.{patch}+{build}）")
        return 0

    print("✗ 版本显示串和 pubspec 对不上")
    print(f"    app_version.dart : {display}")
    print(f"    pubspec.yaml     : {major}.{minor}.{patch}+{build}")
    print(f"    应该是           : {want}")
    print()
    print("  改 app_version.dart 里的 kVersionDisplay，或者把这个脚本接进发版流程。")
    print("  不改的话「关于」页会一直显示上一个版本的号。")
    return 1


if __name__ == "__main__":
    sys.exit(main())