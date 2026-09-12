#!/usr/bin/env python3
"""把 assets/branding/ico-frames 里的 PNG 帧装进 .ico 容器。

Windows 的 ICO 允许内嵌 PNG（Vista+，本项目只支持 Win10+），所以不用
自己编码 BMP。尺寸档和用途：

    app_icon.ico   16/24/32/48/64/128/256  exe、设置窗口、启动闪屏
    tray.ico       16/24/32/48             托盘（Windows 只挑 16/32）
    assets/tray.ico、windows/runner/resources/app_icon.ico

帧由 test/logo_asset_gen_test.dart 生成（Canvas 按 SVG 同一几何重画），
顺序：先跑 flutter test 生成帧，再跑本脚本。

    flutter test test/logo_asset_gen_test.dart
    python tool/make_icons.py
"""
import os
import struct
import sys

FRAMES_DIR = os.path.join('assets', 'branding', 'ico-frames')
APP_ICON = os.path.join('windows', 'runner', 'resources', 'app_icon.ico')
TRAY_ICON = os.path.join('assets', 'tray.ico')


def build_ico(sizes, out_path):
    entries, blobs, offset = [], [], 6 + 16 * len(sizes)
    for size in sizes:
        frame = os.path.join(FRAMES_DIR, f'mark-{size}.png')
        if not os.path.exists(frame):
            sys.exit(f'缺少图标帧 {frame}，先跑 flutter test test/logo_asset_gen_test.dart')
        with open(frame, 'rb') as f:
            data = f.read()
        if data[:8] != b'\x89PNG\r\n\x1a\n':
            sys.exit(f'{frame} 不是 PNG')
        entries.append(struct.pack(
            '<BBBBHHII',
            0 if size >= 256 else size,   # 宽（256 用 0 表示）
            0 if size >= 256 else size,   # 高
            0, 0, 1, 32, len(data), offset))
        blobs.append(data)
        offset += len(data)

    with open(out_path, 'wb') as f:
        f.write(struct.pack('<HHH', 0, 1, len(sizes)))
        for e in entries:
            f.write(e)
        for b in blobs:
            f.write(b)
    print(f'已写入 {out_path}（{",".join(str(s) for s in sizes)}）')


def main():
    build_ico([16, 24, 32, 48, 64, 128, 256], APP_ICON)
    build_ico([16, 24, 32, 48], TRAY_ICON)


if __name__ == '__main__':
    main()
