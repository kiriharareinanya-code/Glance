"""部署到本机正式安装目录并启动（自证用）。

按项目约定：
  - 覆盖前必须先 taskkill，否则占用中的 exe/dll 覆盖会失败；
  - 启动**必须**用 explorer.exe，不能用 subprocess.Popen ——
    Popen 起的进程留在本命令的 Job 里，脚本一退出 Job 关闭，
    程序被连带强杀，且现场零痕迹（曾因此被折腾一个多小时）。
"""

import shutil
import subprocess
import sys
from pathlib import Path

SRC = Path(r"C:\Users\81157\Documents\work\Vectra\build\windows\x64\runner\Release")
DST = Path(r"C:\Users\81157\Glance")
EXE = "glance.exe"

# **绝不能覆盖**的目录：用户数据。
#
# `build/.../Release/` 下如果残留一份 `userdata/`（以前直接从编译产物目录
# 启动过程序就会有，而且 `flutter build` 不会清它），上面那个"整个目录
# copytree"会把这**几周前的旧 config.json 覆盖到用户的正式安装里**——
# 表现就是"每次重新编译部署后，设置/布局都退回某个旧样子"。
#
# 用户的设置只属于 DST 那一份，编译产物里的是历史副本，永远不该参与部署。
SKIP = {"userdata"}


def kill() -> None:
    subprocess.run(["taskkill", "/F", "/IM", EXE],
                   capture_output=True)
    # 等进程真正退干净，否则文件还被占着
    subprocess.run(["timeout", "/T", "2", "/NOBREAK"],
                   capture_output=True, shell=True)


def deploy() -> None:
    kill()
    if not SRC.exists():
        sys.exit(f"编译产物不存在：{SRC}")
    skipped = []
    for p in SRC.iterdir():
        if p.name in SKIP:
            skipped.append(p.name)
            continue
        if p.is_dir():
            shutil.copytree(p, DST / p.name, dirs_exist_ok=True)
        else:
            shutil.copy2(p, DST / p.name)
    print(f"已部署 {SRC} -> {DST}")
    if skipped:
        print(f"（已跳过用户数据：{', '.join(skipped)}）")



def launch() -> None:
    # 必须 explorer.exe：见模块 docstring。
    subprocess.run(["explorer.exe", str(DST / EXE)], capture_output=True)
    print("已通过 explorer.exe 启动")


if __name__ == "__main__":
    deploy()
    launch()
