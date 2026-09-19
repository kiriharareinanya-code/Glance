"""生成组件库用的静态概览图。

背景：组件库页原先挂的是 BuiltinPreview——把组件真的跑起来（时钟在走、
天气在拉 API、歌词在读 SMTC）。反馈里明确要求这一页改成**写死的静态概览图**：
不要再有实时渲染、不要再发动态请求。所以这里为每个内置组件预先画一张
PNG，运行时只用 Image.asset 显示，零请求、零定时器。

本脚本是**离线生成工具**（改组件外观时手动跑一次，把结果提交进仓库），
不参与运行时。字体用系统里的微软雅黑，和卡片上的观感接近。

用法：
    python tools/gen_previews.py
输出：
    assets/previews/<id>.png   （默认尺寸 3x 默认格，2 倍图）
"""

from __future__ import annotations

import math
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "previews")

# 和 core/grid.dart 的 kDefaultCell / kDefaultGap 对齐
CELL = 112
GAP = 12
SCALE = 2  # 出 2 倍图，窄卡片缩小时也不糊

# 两套主题的配色。深色对齐磁贴深色卡片，浅色对齐面板浅色（_PanelColors.light：
# 纯白卡片、深墨文字、加深一档的主题蓝）。绘制函数引用的都是模块级常量，
# set_theme() 换掉它们之后重新生成即可，函数本身不用动。
THEMES = {
    "dark": dict(
        CARD_BG=(42, 42, 46, 255),
        FG=(255, 255, 255, 255),
        ACCENT=(124, 199, 255, 255),
        GREEN=(124, 227, 139, 255),
        WARM=(255, 158, 125, 255),
        MUTED=(255, 255, 255, 130),
        FG_BASE=(255, 255, 255),
    ),
    "light": dict(
        CARD_BG=(255, 255, 255, 255),
        FG=(22, 24, 28, 255),
        ACCENT=(21, 101, 192, 255),
        GREEN=(46, 125, 50, 255),
        WARM=(198, 40, 40, 255),
        MUTED=(22, 24, 28, 130),
        FG_BASE=(22, 24, 28),
    ),
}

CUR = THEMES["dark"]
CARD_BG = CUR["CARD_BG"]
FG = CUR["FG"]
ACCENT = CUR["ACCENT"]
GREEN = CUR["GREEN"]
WARM = CUR["WARM"]
MUTED = CUR["MUTED"]


def set_theme(name: str) -> None:
    """切换全局配色。要在每次生成一批图之前调用。"""
    global CUR, CARD_BG, FG, ACCENT, GREEN, WARM, MUTED
    CUR = THEMES[name]
    CARD_BG = CUR["CARD_BG"]
    FG = CUR["FG"]
    ACCENT = CUR["ACCENT"]
    GREEN = CUR["GREEN"]
    WARM = CUR["WARM"]
    MUTED = CUR["MUTED"]


def _fg(alpha: int):
    """带 alpha 的前景装饰色（胶囊、发丝线、次级文字那些）。

    以前全部写死白色半透明，浅色卡片上会直接消失；这里跟着主题翻转：
    深色卡片上是白，浅色卡片上是深墨色。
    """
    b = CUR["FG_BASE"]
    return (b[0], b[1], b[2], alpha)


def _font(size: int) -> ImageFont.FreeTypeFont:
    """找一个能显示中文的字体。"""
    for name in ("msyh.ttc", "msyhbd.ttc", "simhei.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _size(cols: int, rows: int) -> tuple[int, int]:
    w = (cols * CELL + (cols - 1) * GAP) * SCALE
    h = (rows * CELL + (rows - 1) * GAP) * SCALE
    return w, h


def _canvas(cols: int, rows: int):
    w, h = _size(cols, rows)
    img = Image.new("RGBA", (w, h), CARD_BG)
    # 半透明的胶囊/圆底不能直接画在 img 上：PIL 的 ImageDraw 是**替换**像素
    # 而不是 alpha 混合，半透明白会变成纯白实心块（第一版就踩了这个坑）。
    # 拆成两层——底层画不透明内容，overlay 攒半透明件，最后 alpha_composite。
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img), ImageDraw.Draw(overlay), overlay, w, h


def _flat(img: Image.Image, overlay: Image.Image) -> Image.Image:
    """把半透明层压到不透明底上，返回最终图。"""
    return Image.alpha_composite(img, overlay)


def _t(d, xy, text, size, fill, anchor="la", bold=False):
    d.text(xy, text, font=_font(int(size * SCALE)), fill=fill, anchor=anchor)


def _dot(d, x, y, color, r=4):
    r *= SCALE
    d.ellipse([x - r, y - r, x + r, y + r], fill=color)


PAD = 18 * SCALE


# --------------------------------------------------------------------------- #
# 每个组件一张：画的是该组件**最有代表性的一帧**，内容写死
# --------------------------------------------------------------------------- #

def clock() -> Image.Image:
    img, d, o, ov, w, h = _canvas(2, 2)
    _t(d, (PAD, PAD), "9 月 19 日 周六", 13, MUTED)
    # 时分横排：小时粗、冒号淡、分钟细 + 主色
    _t(d, (PAD, h * 0.42), "01", 46, ACCENT, anchor="lm")
    _t(d, (PAD + 96 * SCALE, h * 0.42), ":", 40, _fg(90), anchor="lm")
    _t(d, (PAD + 130 * SCALE, h * 0.42), "49", 46, ACCENT, anchor="lm")
    return _flat(img, ov)


def weather() -> Image.Image:
    img, d, o, ov, w, h = _canvas(3, 2)
    _dot(d, PAD + 4, PAD + 8, ACCENT)
    _t(d, (PAD + 14, PAD - 2), "杭州", 13, MUTED)
    _t(d, (PAD, h * 0.28), "24", 48, FG)
    _t(d, (PAD + 62 * SCALE, h * 0.28 + 8), "°", 22, MUTED)
    # 右上天气图标（圆底 + 太阳）
    cx, cy, r = w - PAD - 40 * SCALE, PAD + 20 * SCALE, 20 * SCALE
    o.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 215, 154, 38))
    d.ellipse([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42],
              fill=(255, 215, 154, 255))
    _t(d, (cx, cy + r + 8), "晴", 12, MUTED, anchor="ma")
    # 徽章行：底走 overlay，字走底层（不透明）
    bx = PAD
    by = h * 0.56
    for label in ("体感 26°", "湿度 62%", "8km/h", "UV 3"):
        tw = d.textlength(label, font=_font(int(11 * SCALE)))
        box_w = tw + 16 * SCALE
        o.rounded_rectangle([bx, by, bx + box_w, by + 22 * SCALE],
                            radius=9 * SCALE, fill=_fg(18))
        _t(d, (bx + 8 * SCALE, by + 4 * SCALE), label, 11, _fg(190))
        bx += box_w + 6 * SCALE
    # 5 天预报
    d.line([PAD, h * 0.72, w - PAD, h * 0.72], fill=_fg(26), width=1)
    labels = [("今天", "26°", True), ("周日", "24°", False), ("周一", "22°", False),
              ("周二", "25°", False), ("周三", "27°", False)]
    cw = (w - PAD * 2) / 5
    for i, (day, t, today) in enumerate(labels):
        x = PAD + cw * i + cw / 2
        if today:
            o.rounded_rectangle([PAD + cw * i + 2, h * 0.75, PAD + cw * (i + 1) - 2, h - PAD],
                                radius=10 * SCALE, fill=_fg(28))
        _t(d, (x, h * 0.78), day, 11, MUTED, anchor="ma")
        _t(d, (x, h * 0.86), t, 12, FG, anchor="ma")
    return _flat(img, ov)


def todo() -> Image.Image:
    img, d, o, ov, w, h = _canvas(2, 3)
    _dot(d, PAD + 4, PAD + 10, GREEN)
    _t(d, (PAD + 14, PAD), "待办", 13, FG)
    # 徽章
    bx = w - PAD - 74 * SCALE
    o.rounded_rectangle([bx, PAD + 2, w - PAD, PAD + 24 * SCALE],
                        radius=8 * SCALE, fill=_fg(18))
    _t(d, (bx + 10 * SCALE, PAD + 6 * SCALE), "2 项未完成", 11, _fg(150))
    # 输入框
    o.rounded_rectangle([PAD, h * 0.17, w - PAD, h * 0.17 + 34 * SCALE],
                        radius=8 * SCALE, fill=_fg(14))
    _t(d, (PAD + 10 * SCALE, h * 0.17 + 9 * SCALE), "添加一项，回车确认", 11, MUTED)
    # 列表
    y = h * 0.30
    for text, done in (("买咖啡豆", False), ("看一集动画", True), ("复习歌词卡排版", False)):
        box = 16 * SCALE
        o.rounded_rectangle([PAD, y, PAD + box, y + box], radius=5 * SCALE,
                            outline=_fg(70), width=2 * SCALE)
        if done:
            o.rectangle([PAD + 4 * SCALE, y + 4 * SCALE,
                         PAD + box - 4 * SCALE, y + box - 4 * SCALE],
                        fill=_fg(90))
        _t(d, (PAD + box + 10 * SCALE, y - 1 * SCALE), text, 12,
           _fg(90) if done else FG)
        y += 40 * SCALE
    return _flat(img, ov)


def calendar() -> Image.Image:
    img, d, o, ov, w, h = _canvas(4, 4)
    _t(d, (PAD, PAD), "2026年9月", 17, FG)
    o.rounded_rectangle([PAD + 116 * SCALE, PAD + 3 * SCALE,
                         PAD + 116 * SCALE + 42 * SCALE, PAD + 24 * SCALE],
                        radius=5 * SCALE, fill=_fg(20))
    _t(d, (PAD + 124 * SCALE, PAD + 6 * SCALE), "今天", 10, _fg(200))
    # 农历行
    y0 = PAD + 34 * SCALE
    _t(d, (PAD, y0), "八月初九  丙午年 属马", 12, _fg(150))
    # 星期头
    heads = ["一", "二", "三", "四", "五", "六", "日"]
    gy = y0 + 30 * SCALE
    cw = (w - PAD * 2) / 7
    for i, hd in enumerate(heads):
        _t(d, (PAD + cw * i + cw / 2, gy), hd, 13, _fg(160), anchor="ma")
    # 6 行日期，写死 9 月
    days = [
        ["31", "1", "2", "3", "4", "5", "6"],
        ["7", "8", "9", "10", "11", "12", "13"],
        ["14", "15", "16", "17", "18", "19", "20"],
        ["21", "22", "23", "24", "25", "26", "27"],
        ["28", "29", "30", "1", "2", "3", "4"],
        ["5", "6", "7", "8", "9", "10", "11"],
    ]
    subs = [
        ["十四", "初二", "初三", "初四", "初五", "初六", "初七"],
        ["初八", "初九", "初十", "十一", "十二", "十三", "十四"],
        ["十五", "十六", "十七", "十八", "十九", "二十", "廿一"],
        ["廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八"],
        ["廿九", "三十", "八月", "初二", "初三", "初四", "初五"],
        ["初六", "初七", "初八", "初九", "初十", "十一", "十二"],
    ]
    rh = (h - gy - 40 * SCALE) / 6
    for r in range(6):
        for c in range(7):
            cx = PAD + cw * c + cw / 2
            cy = gy + 26 * SCALE + rh * r + rh / 2
            today = (r == 2 and c == 5)
            off = r >= 4
            if today:
                rad = 19 * SCALE
                d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(41, 182, 246, 255))
            col = (11, 17, 22, 255) if today else (
                (255, 138, 107, 255) if c >= 5 else (_fg(90) if off else _fg(255)))
            _t(d, (cx, cy - 12 * SCALE), days[r][c], 17, col, anchor="ma")
            _t(d, (cx, cy + 6 * SCALE), subs[r][c], 11,
               (11, 17, 22, 230) if today else _fg(110))
    return _flat(img, ov)


def lyrics() -> Image.Image:
    img, d, o, ov, w, h = _canvas(5, 3)
    art = 150 * SCALE
    d.rounded_rectangle([PAD, PAD, PAD + art, PAD + art], radius=12 * SCALE,
                        fill=(90, 110, 140, 255))
    # 封面里画同心圆当占位图案（真封面是专辑图）
    ccx, ccy = PAD + art / 2, PAD + art / 2
    for rr in (46, 30, 16):
        o.ellipse([ccx - rr * SCALE, ccy - rr * SCALE,
                   ccx + rr * SCALE, ccy + rr * SCALE],
                  outline=_fg(60), width=2 * SCALE)
    _t(d, (PAD, PAD + art + 10 * SCALE), "夏夕空", 13, FG)
    _t(d, (PAD, PAD + art + 30 * SCALE), "中孝介", 11, MUTED)

    # 右侧：上一首 / 播放 / 下一首 + 进度条 + 时间 + 歌词
    rx = PAD + art + 18 * SCALE
    cy = PAD + 18 * SCALE
    # 三个控件按钮用几何图形画，避免字体缺 ▶/⏸ 这类符号变成豆腐块
    def tri(cx, cy, size, direction, alpha=150):
        h2 = size / 2
        if direction == "play":
            pts = [(cx - h2 * 0.6, cy - h2), (cx - h2 * 0.6, cy + h2), (cx + h2 * 0.8, cy)]
        elif direction == "next":
            pts = [(cx - h2, cy - h2), (cx - h2, cy + h2), (cx + h2 * 0.4, cy)]
        else:  # prev
            pts = [(cx + h2, cy - h2), (cx + h2, cy + h2), (cx - h2 * 0.4, cy)]
        d.polygon(pts, fill=(255, 255, 255, alpha))

    for i, direction in enumerate(("prev", "play", "next")):
        bx = rx + i * 34 * SCALE
        if direction == "play":
            o.ellipse([bx - 4 * SCALE, cy - 20 * SCALE,
                       bx + 34 * SCALE, cy + 18 * SCALE], fill=_fg(26))
        tri(bx + 14 * SCALE, cy, 16 * SCALE, direction,
            220 if direction == "play" else 130)

    # 进度条
    bar_y = cy + 42 * SCALE
    bar_w = w - rx - PAD
    d.rounded_rectangle([rx, bar_y, rx + bar_w, bar_y + 3 * SCALE],
                        radius=2 * SCALE, fill=_fg(51))
    d.rounded_rectangle([rx, bar_y, rx + bar_w * 0.42, bar_y + 3 * SCALE],
                        radius=2 * SCALE, fill=_fg(255))
    _t(d, (rx, bar_y + 8 * SCALE), "1:24", 11, MUTED)
    _t(d, (rx + bar_w, bar_y + 8 * SCALE), "3:18", 11, MUTED, anchor="ra")

    # 歌词：当前行高亮放大，前后行淡出（真机就是这个观感）
    ly = bar_y + 44 * SCALE
    for i, line in enumerate(("夏の夕空に", "君の声が響く", "遠い記憶の中で", "still I hear you")):
        cur = i == 1
        _t(d, (rx, ly), line, 16 if cur else 13,
           (255, 255, 255, 255 if cur else 100))
        ly += 36 * SCALE
    return _flat(img, ov)


SPECS = {
    "clock": clock,
    "weather": weather,
    "todo": todo,
    "calendar": calendar,
    "lyrics": lyrics,
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    # 深色是默认命名（<id>.png，保持旧文件名兼容），浅色加 -light 后缀。
    # 面板运行时按当前明暗挑一张（见 ui/panel_preview.dart 的 assetPath）。
    for theme in ("dark", "light"):
        set_theme(theme)
        suffix = "" if theme == "dark" else "-light"
        for pid, fn in SPECS.items():
            img = fn()
            path = os.path.join(OUT, f"{pid}{suffix}.png")
            img.save(path)
            print(f"generated {path}  {img.size[0]}x{img.size[1]}  [{theme}]")


if __name__ == "__main__":
    main()
