# -*- coding: utf-8 -*-
import argparse
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "Textures"
S = 3

FONT_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")
FONT_REGULAR = Path(r"C:\Windows\Fonts\msyh.ttc")


def sc(value):
    return int(round(value * S))


def box(values):
    return tuple(sc(v) for v in values)


def rgba(hex_color, alpha=255):
    hex_color = hex_color.lstrip("#")
    return (
        int(hex_color[0:2], 16),
        int(hex_color[2:4], 16),
        int(hex_color[4:6], 16),
        alpha,
    )


def font(path, size):
    return ImageFont.truetype(str(path), sc(size))


def new_image(width, height, fill=(0, 0, 0, 0)):
    return Image.new("RGBA", (sc(width), sc(height)), fill)


def downsample(image):
    return image.resize((image.width // S, image.height // S), Image.Resampling.LANCZOS)


def save(image, name):
    OUT.mkdir(parents=True, exist_ok=True)
    final = downsample(image)
    final.save(OUT / name)
    return final


def vertical_gradient(width, height, stops):
    image = new_image(width, height)
    draw = ImageDraw.Draw(image)
    h = image.height
    stops = sorted(stops)
    for y in range(h):
        pos = y / max(1, h - 1)
        left = stops[0]
        right = stops[-1]
        for i in range(len(stops) - 1):
            if stops[i][0] <= pos <= stops[i + 1][0]:
                left = stops[i]
                right = stops[i + 1]
                break
        span = max(0.0001, right[0] - left[0])
        t = (pos - left[0]) / span
        color = tuple(int(left[1][j] + (right[1][j] - left[1][j]) * t) for j in range(4))
        draw.line([(0, y), (image.width, y)], fill=color)
    return image


def rounded_rect(draw, values, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box(values), radius=sc(radius), fill=fill, outline=outline, width=sc(width))


def shadowed_round_rect(width, height, rect, radius, fill, outline, outline_width, shadow_box, shadow_radius, shadow_color):
    image = new_image(width, height)
    shadow = new_image(width, height)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, shadow_box, shadow_radius, shadow_color)
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(2.5)))
    image.alpha_composite(shadow)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, rect, radius, fill, outline, outline_width)
    return image


def add_rotated_line(image, x, y, w, h, angle, color):
    layer = new_image(w + 18, h + 18)
    draw = ImageDraw.Draw(layer)
    rounded_rect(draw, (9, 9, 9 + w, 9 + h), h / 2, color)
    rotated = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    image.alpha_composite(rotated, (sc(x), sc(y)))


def draw_center(draw, text, center_x, top_y, text_font, fill, stroke_width=0, stroke_fill=None, line_gap=0):
    lines = text.split("\n")
    bboxes = [draw.textbbox((0, 0), line, font=text_font, stroke_width=sc(stroke_width)) for line in lines]
    heights = [bbox[3] - bbox[1] for bbox in bboxes]
    y = sc(top_y)
    for line, bbox, h in zip(lines, bboxes, heights):
        w = bbox[2] - bbox[0]
        x = sc(center_x) - w // 2 - bbox[0]
        draw.text(
            (x, y - bbox[1]),
            line,
            font=text_font,
            fill=fill,
            stroke_width=sc(stroke_width),
            stroke_fill=stroke_fill,
        )
        y += h + sc(line_gap)


def text_width(draw, text, text_font, stroke_width=0):
    bbox = draw.textbbox((0, 0), text, font=text_font, stroke_width=sc(stroke_width))
    return bbox[2] - bbox[0]


def draw_scene_bg():
    image = vertical_gradient(
        390,
        844,
        [
            (0.00, rgba("#86dcff")),
            (0.34, rgba("#dff7ff")),
            (0.70, rgba("#ffe8a5")),
            (1.00, rgba("#ffb05c")),
        ],
    )
    draw = ImageDraw.Draw(image)

    # Sun and soft clouds.
    draw.ellipse(box((276, 75, 340, 139)), fill=rgba("#ffd447"))
    draw.ellipse(box((292, 88, 316, 112)), fill=rgba("#fff7a8"))

    # City skyline.
    city_y = 226
    city_h = 180
    city_mask = Image.new("L", (sc(390), sc(city_h)), 0)
    city_draw = ImageDraw.Draw(city_mask)
    city_draw.polygon(
        [
            (sc(0), sc(city_h * 0.42)),
            (sc(27), sc(city_h * 0.42)),
            (sc(27), sc(city_h * 0.16)),
            (sc(70), sc(city_h * 0.16)),
            (sc(70), sc(city_h * 0.32)),
            (sc(109), sc(city_h * 0.32)),
            (sc(109), sc(city_h * 0.06)),
            (sc(168), sc(city_h * 0.06)),
            (sc(168), sc(city_h * 0.24)),
            (sc(203), sc(city_h * 0.24)),
            (sc(203), sc(city_h * 0.36)),
            (sc(250), sc(city_h * 0.36)),
            (sc(250), sc(city_h * 0.12)),
            (sc(304), sc(city_h * 0.12)),
            (sc(304), sc(city_h * 0.28)),
            (sc(351), sc(city_h * 0.28)),
            (sc(351), sc(city_h * 0.18)),
            (sc(390), sc(city_h * 0.18)),
            (sc(390), sc(city_h)),
            (0, sc(city_h)),
        ],
        fill=230,
    )
    city = vertical_gradient(
        390,
        city_h,
        [
            (0.0, rgba("#72c6e4", 225)),
            (1.0, rgba("#4198c2", 225)),
        ],
    )
    city_lines = ImageDraw.Draw(city)
    for x in [62, 143, 226, 317]:
        city_lines.rectangle(box((x, 0, x + 6, city_h)), fill=(255, 255, 255, 45))
    image.paste(city, (0, sc(city_y)), city_mask)

    # Perspective road.
    road_w, road_h = 574, 472
    road_x, road_y = -92, 236
    road = vertical_gradient(
        road_w,
        road_h,
        [
            (0.00, rgba("#5e6b75")),
            (0.48, rgba("#364451")),
            (1.00, rgba("#25313b")),
        ],
    )
    road_draw = ImageDraw.Draw(road)
    road_draw.rectangle(box((road_w * 0.34, 0, road_w * 0.36, road_h)), fill=(255, 255, 255, 38))
    road_draw.rectangle(box((road_w * 0.64, 0, road_w * 0.66, road_h)), fill=(255, 255, 255, 38))

    road_mask = Image.new("L", (sc(road_w), sc(road_h)), 0)
    mask_draw = ImageDraw.Draw(road_mask)
    mask_draw.polygon(
        [
            (sc(road_w * 0.42), 0),
            (sc(road_w * 0.58), 0),
            (sc(road_w * 0.91), sc(road_h)),
            (sc(road_w * 0.09), sc(road_h)),
        ],
        fill=255,
    )
    image.paste(road, (sc(road_x), sc(road_y)), road_mask)
    return image


def draw_cloud_one():
    image = new_image(104, 48)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (0, 11, 70, 39), 14, (255, 255, 255, 200))
    draw.ellipse(box((20, 0, 54, 34)), fill=(255, 255, 255, 200))
    draw.ellipse(box((44, 8, 90, 40)), fill=(255, 255, 255, 200))
    return save(image, "home_cloud_one.png")


def draw_cloud_two():
    image = new_image(122, 58)
    draw = ImageDraw.Draw(image)
    draw.ellipse(box((50, 9, 122, 41)), fill=(255, 255, 255, 178))
    draw.ellipse(box((32, 0, 82, 50)), fill=(255, 255, 255, 150))
    rounded_rect(draw, (44, 17, 108, 44), 14, (255, 255, 255, 165))
    rounded_rect(draw, (0, 28, 50, 54), 13, (255, 255, 255, 178))
    draw.ellipse(box((12, 20, 42, 50)), fill=(255, 255, 255, 178))
    draw.ellipse(box((34, 28, 69, 55)), fill=(255, 255, 255, 178))
    return save(image, "home_cloud_two.png")


def draw_lane_strip(name="home_lane_strip.png", phase=0):
    lane_w = 12
    lane_h = 530
    image = new_image(lane_w, lane_h)
    draw = ImageDraw.Draw(image)
    for y in range(-58 + phase, lane_h + 58, 58):
        rounded_rect(draw, (3, y, 9, y + 28), 3, (255, 255, 255, 218))
    return save(image, name)


def draw_lane_strip_frames():
    phases = [0, 10, 19, 29, 39, 48]
    for index, phase in enumerate(phases):
        name = "home_lane_strip.png" if index == 0 else f"home_lane_strip_{index}.png"
        draw_lane_strip(name, phase)


def draw_speed_line(name, width, alpha):
    image = new_image(width + 22, 23)
    add_rotated_line(image, 0, 5, width, 5, -16, (255, 255, 255, alpha))
    return save(image, name)


def draw_rider_shadow():
    shadow = new_image(148, 44)
    draw = ImageDraw.Draw(shadow)
    draw.ellipse(box((12, 10, 136, 34)), fill=(7, 17, 22, 62))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(3)))
    return save(shadow, "home_rider_shadow.png")


def draw_bottom_fade():
    fade = vertical_gradient(
        390,
        222,
        [
            (0.00, (255, 247, 222, 0)),
            (0.18, (255, 247, 222, 220)),
            (1.00, rgba("#fff3c6")),
        ],
    )
    return save(fade, "home_bottom_fade.png")


def draw_coin_icon():
    image = new_image(26, 26)
    draw = ImageDraw.Draw(image)
    draw.ellipse(box((2, 2, 23, 23)), fill=rgba("#ff9f1a"))
    draw.ellipse(box((2, 2, 23, 23)), outline=(120, 68, 0, 55), width=sc(1))
    draw.ellipse(box((7, 5, 14, 12)), fill=rgba("#fff8a5"))
    return save(image, "home_coin_icon.png")


def save_scene_backgrounds(include_composite=False):
    static_bg = draw_scene_bg()
    save(static_bg, "home_scene_bg_static.png")

    if not include_composite:
        return

    full = Image.open(OUT / "home_scene_bg_static.png").convert("RGBA")
    for name, x, y in [
        ("home_cloud_one.png", 24, 62),
        ("home_cloud_two.png", 236, 110),
        ("home_lane_strip.png", 189, 236),
        ("home_speed_line_a.png", 28, 318),
        ("home_speed_line_b.png", 296, 384),
        ("home_speed_line_c.png", 64, 466),
        ("home_rider_shadow.png", 121, 510),
        ("home_bottom_fade.png", 0, 622),
    ]:
        full.alpha_composite(Image.open(OUT / name).convert("RGBA"), (x, y))
    full.save(OUT / "home_scene_bg.png")


def draw_title():
    image = new_image(250, 138)
    draw = ImageDraw.Draw(image)
    f = font(FONT_BOLD, 58)
    draw_center(draw, "外卖", 125, 0, f, rgba("#d9570f"), stroke_width=1, stroke_fill=rgba("#d9570f"), line_gap=-4)
    draw_center(draw, "冲冲冲", 125, 54, f, rgba("#d9570f"), stroke_width=1, stroke_fill=rgba("#d9570f"), line_gap=-4)
    draw_center(draw, "外卖", 125, 0, f, rgba("#ffffff"), line_gap=-4)
    draw_center(draw, "冲冲冲", 125, 54, f, rgba("#ffd447"), line_gap=-4)
    return save(image, "home_title.png")


def draw_subtitle_badge():
    image = shadowed_round_rect(
        168,
        34,
        (2, 2, 166, 30),
        15,
        rgba("#fff7df", 232),
        (255, 255, 255, 220),
        2,
        (5, 6, 163, 32),
        15,
        (117, 63, 6, 34),
    )
    return save(image, "home_subtitle_badge.png")


def draw_level_badge():
    image = new_image(166, 72)
    shadow = new_image(166, 72)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (6, 8, 160, 64), 16, (103, 48, 4, 64))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.4)))
    image.alpha_composite(shadow)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (5, 0, 159, 58), 16, rgba("#253645"), (255, 255, 255, 184), 3)
    inner = vertical_gradient(154, 52, [(0, rgba("#253645")), (1, rgba("#14202b"))])
    mask = Image.new("L", (sc(154), sc(52)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(154), sc(52)), radius=sc(13), fill=255)
    image.paste(inner, (sc(8), sc(3)), mask)
    return save(image, "home_level_badge.png")


def draw_coin_badge():
    image = new_image(114, 58)
    shadow = new_image(114, 58)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (4, 7, 110, 55), 24, (103, 48, 4, 64))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.2)))
    image.alpha_composite(shadow)
    body = vertical_gradient(108, 50, [(0, rgba("#ffad36")), (1, rgba("#ff8618"))])
    mask = Image.new("L", (sc(108), sc(50)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(108), sc(50)), radius=sc(25), fill=255)
    image.paste(body, (sc(3), 0), mask)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (3, 0, 111, 50), 25, None, (255, 255, 255, 184), 3)
    draw.ellipse(box((24, 14, 45, 35)), fill=rgba("#ff9f1a"))
    draw.ellipse(box((24, 14, 45, 35)), outline=(120, 68, 0, 55), width=sc(1))
    draw.ellipse(box((29, 17, 36, 24)), fill=rgba("#fff8a5"))
    return save(image, "home_coin_badge.png")


def draw_coin_badge_base():
    image = new_image(114, 58)
    shadow = new_image(114, 58)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (4, 7, 110, 55), 24, (103, 48, 4, 64))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.2)))
    image.alpha_composite(shadow)
    body = vertical_gradient(108, 50, [(0, rgba("#ffad36")), (1, rgba("#ff8618"))])
    mask = Image.new("L", (sc(108), sc(50)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(108), sc(50)), radius=sc(25), fill=255)
    image.paste(body, (sc(3), 0), mask)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (3, 0, 111, 50), 25, None, (255, 255, 255, 184), 3)
    return save(image, "home_coin_badge_base.png")


def draw_xp_assets():
    track = new_image(132, 8)
    draw = ImageDraw.Draw(track)
    rounded_rect(draw, (0, 0, 132, 8), 4, (255, 255, 255, 46))
    save(track, "home_xp_track.png")

    fill = vertical_gradient(132, 8, [(0, rgba("#ffd447")), (1, rgba("#27c96b"))])
    mask = Image.new("L", (sc(132), sc(8)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(132), sc(8)), radius=sc(4), fill=255)
    filled = new_image(132, 8)
    filled.paste(fill, (0, 0), mask)
    save(filled, "home_xp_fill.png")


def draw_order_sign():
    base = new_image(144, 130)
    draw = ImageDraw.Draw(base)
    shadow = new_image(144, 130)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (13, 13, 131, 74), 12, (35, 20, 0, 62))
    shadow_draw.rounded_rectangle(box((68, 68, 76, 124)), radius=sc(4), fill=(35, 20, 0, 62))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(3)))
    base.alpha_composite(shadow)
    body = vertical_gradient(118, 60, [(0, rgba("#ffe16e")), (1, rgba("#ffb231"))])
    mask = Image.new("L", (sc(118), sc(60)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(118), sc(60)), radius=sc(12), fill=255)
    base.paste(body, (sc(13), sc(10)), mask)
    rounded_rect(draw, (13, 10, 131, 70), 12, None, rgba("#8c3e06"), 3)
    rounded_rect(draw, (68, 68, 76, 122), 4, rgba("#8c3e06"))
    rotated = base.rotate(7, resample=Image.Resampling.BICUBIC, expand=True)
    save(rotated, "home_order_sign.png")


def draw_rider():
    image = new_image(188, 188)
    bg = vertical_gradient(188, 188, [(0, (230, 247, 255, 255)), (1, (255, 243, 216, 255))])
    mask = Image.new("L", (sc(188), sc(188)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(188), sc(188)), radius=sc(42), fill=255)
    image.paste(bg, (0, 0), mask)
    draw = ImageDraw.Draw(image)
    draw.ellipse(box((44, 150, 144, 174)), fill=(24, 49, 62, 38))
    draw.pieslice(box((52, 42, 136, 126)), 180, 360, fill=rgba("#ff8a1f"))
    draw.ellipse(box((62, 54, 126, 118)), fill=rgba("#ffd1a6"))
    draw.rectangle(box((62, 72, 126, 86)), fill=rgba("#314657"))
    draw.ellipse(box((80, 82, 88, 90)), fill=rgba("#17212b"))
    draw.ellipse(box((104, 82, 112, 90)), fill=rgba("#17212b"))
    draw.arc(box((80, 94, 112, 112)), 20, 160, fill=rgba("#17212b"), width=sc(4))
    rounded_rect(draw, (70, 112, 120, 168), 14, rgba("#ff8a1f"))
    draw.polygon([box((60, 112))[0:2], box((34, 150))[0:2], box((48, 158))[0:2], box((76, 122))[0:2]], fill=rgba("#2f80ed"))
    draw.polygon([box((120, 118))[0:2], box((150, 150))[0:2], box((160, 140))[0:2], box((134, 112))[0:2]], fill=rgba("#2f80ed"))
    rounded_rect(draw, (126, 104, 168, 150), 8, rgba("#ffcf4a"))
    return save(image, "home_rider.png")


def draw_start_button(name, pressed=False):
    image = new_image(346, 84)
    shadow = new_image(346, 84)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (2, 10, 344, 78), 22, (103, 48, 4, 64))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.4)))
    image.alpha_composite(shadow)
    top = "#d36a15" if pressed else "#ffb23b"
    mid = "#c65d12" if pressed else "#ff8618"
    bottom = "#a7470d" if pressed else "#d9570f"
    body = vertical_gradient(338, 66, [(0, rgba(top)), (0.56, rgba(mid)), (1, rgba(bottom))])
    mask = Image.new("L", (sc(338), sc(66)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(338), sc(66)), radius=sc(22), fill=255)
    image.paste(body, (sc(4), sc(1 if pressed else 0)), mask)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (4, 0 if not pressed else 1, 342, 66 if not pressed else 67), 22, None, (255, 255, 255, 240), 4)
    add_rotated_line(image, 20, 30 if not pressed else 32, 34, 8, 18, (255, 255, 255, 188))
    add_rotated_line(image, 292, 30 if not pressed else 32, 34, 8, -18, (255, 255, 255, 188))
    return save(image, name)


def draw_round_button(name, top, bottom, shadow_color):
    image = new_image(64, 66)
    shadow = new_image(64, 66)
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(box((4, 7, 60, 63)), fill=shadow_color)
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.2)))
    image.alpha_composite(shadow)
    body = vertical_gradient(58, 58, [(0, rgba(top)), (1, rgba(bottom))])
    mask = Image.new("L", (sc(58), sc(58)), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, sc(58), sc(58)), fill=255)
    image.paste(body, (sc(3), 0), mask)
    draw = ImageDraw.Draw(image)
    draw.ellipse(box((3, 0, 61, 58)), outline=(255, 255, 255, 220), width=sc(3))
    return save(image, name)


def draw_dock_button():
    image = new_image(80, 78)
    shadow = new_image(80, 78)
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rect(shadow_draw, (2, 6, 78, 76), 18, (147, 88, 12, 50))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(1.2)))
    image.alpha_composite(shadow)
    body = vertical_gradient(76, 70, [(0, rgba("#fffdf0")), (1, rgba("#ffe2a0"))])
    mask = Image.new("L", (sc(76), sc(70)), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc(76), sc(70)), radius=sc(18), fill=255)
    image.paste(body, (sc(2), 0), mask)
    draw = ImageDraw.Draw(image)
    rounded_rect(draw, (2, 0, 78, 70), 18, None, (255, 255, 255, 235), 3)
    return save(image, "home_dock_button.png")


def draw_dock_icon(name, color):
    image = new_image(30, 30)
    draw = ImageDraw.Draw(image)
    draw.ellipse(box((0, 0, 30, 30)), fill=rgba(color))
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, image.width, image.height), fill=255)
    shade = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shade).rectangle(box((0, 23, 30, 30)), fill=(0, 0, 0, 28))
    shade_alpha = ImageChops.multiply(shade.getchannel("A"), mask)
    shade.putalpha(shade_alpha)
    image.alpha_composite(shade)
    return save(image, name)


def draw_label(draw, text, xy, size, color, bold=True, anchor=None, stroke_width=0, stroke_fill=None):
    f = font(FONT_BOLD if bold else FONT_REGULAR, size)
    draw.text(
        (sc(xy[0]), sc(xy[1])),
        text,
        font=f,
        fill=color,
        anchor=anchor,
        stroke_width=sc(stroke_width),
        stroke_fill=stroke_fill,
    )


def compose_preview():
    bg = Image.open(OUT / "home_scene_bg_static.png").convert("RGBA").resize((sc(390), sc(844)), Image.Resampling.NEAREST)
    image = bg.copy()

    def paste(name, x, y, w=None, h=None):
        item = Image.open(OUT / name).convert("RGBA")
        if w and h:
            item = item.resize((sc(w), sc(h)), Image.Resampling.LANCZOS)
        else:
            item = item.resize((item.width * S, item.height * S), Image.Resampling.NEAREST)
        image.alpha_composite(item, (sc(x), sc(y)))

    paste("home_cloud_one.png", 24, 62)
    paste("home_cloud_two.png", 236, 110)
    paste("home_lane_strip.png", 189, 236)
    paste("home_speed_line_a.png", 28, 318)
    paste("home_speed_line_b.png", 296, 384)
    paste("home_speed_line_c.png", 64, 466)
    paste("home_rider_shadow.png", 121, 510)
    paste("home_bottom_fade.png", 0, 622)
    paste("home_level_badge.png", 7, 8)
    paste("home_coin_badge_base.png", 258, 0)
    paste("home_coin_icon.png", 282, 14)
    paste("home_title.png", 70, 96)
    paste("home_subtitle_badge.png", 111, 220)
    paste("home_order_sign.png", 0, 250)
    paste("home_round_blue.png", 303, 272)
    paste("home_round_green.png", 303, 350)
    paste("home_round_red.png", 303, 428)
    paste("home_rider.png", 101, 314)
    paste("home_start_button_base.png", 22, 630)

    dock_xs = [17, 105, 193, 281]
    for x in dock_xs:
        paste("home_dock_button.png", x, 725)
    icon_names = [
        "home_dock_icon_orange.png",
        "home_dock_icon_blue.png",
        "home_dock_icon_green.png",
        "home_dock_icon_gray.png",
    ]
    for x, icon in zip(dock_xs, icon_names):
        paste(icon, x + 25, 737)

    draw = ImageDraw.Draw(image)
    draw_label(draw, "Lv.1 新手骑手", (26, 20), 15, rgba("#ffffff"))
    draw_label(draw, "最高 0 单 / 连击 0", (26, 42), 11, rgba("#b7e7ff"))
    paste("home_xp_track.png", 27, 56)
    xp = Image.open(OUT / "home_xp_fill.png").convert("RGBA")
    xp = xp.crop((0, 0, int(xp.width * 0.36), xp.height))
    xp = xp.resize((sc(48), sc(8)), Image.Resampling.LANCZOS)
    image.alpha_composite(xp, (sc(27), sc(56)))
    draw_label(draw, "0", (323, 15), 22, rgba("#ffffff"), anchor="la")
    draw_label(draw, "接单上路，准时送达", (195, 226), 13, rgba("#5c2b00"), anchor="ma")
    draw_label(draw, "+¥30", (69, 276), 18, rgba("#a03200"), anchor="ma")
    draw_label(draw, "准时送达\n2 单", (69, 303), 11, rgba("#5c2b00"), anchor="ma")
    draw_label(draw, "任务", (335, 288), 15, rgba("#ffffff"), anchor="ma", stroke_width=1, stroke_fill=(0, 0, 0, 40))
    draw_label(draw, "成就", (335, 366), 15, rgba("#ffffff"), anchor="ma", stroke_width=1, stroke_fill=(0, 0, 0, 40))
    draw_label(draw, "设置", (335, 444), 15, rgba("#ffffff"), anchor="ma", stroke_width=1, stroke_fill=(0, 0, 0, 40))
    draw_label(draw, "接单开冲", (195, 653), 30, rgba("#ffffff"), anchor="ma", stroke_width=1, stroke_fill=(127, 48, 0, 66))
    for x, mark, label in zip(dock_xs, ["骑", "升", "单", "包"], ["骑手", "升级", "订单", "背包"]):
        draw_label(draw, mark, (x + 40, 744), 14, rgba("#ffffff"), anchor="ma")
        draw_label(draw, label, (x + 40, 774), 13, rgba("#633305"), anchor="ma")

    final = downsample(image)
    final.save(OUT / "home_layers_preview.png")


def compose_layer_compare():
    old = Image.open(OUT / "home_scene_bg.png").convert("RGBA")
    rebuilt = Image.open(OUT / "home_scene_bg_static.png").convert("RGBA")

    def paste(dst, name, x, y):
        item = Image.open(OUT / name).convert("RGBA")
        dst.alpha_composite(item, (x, y))

    paste(rebuilt, "home_cloud_one.png", 24, 62)
    paste(rebuilt, "home_cloud_two.png", 236, 110)
    paste(rebuilt, "home_lane_strip.png", 189, 236)
    paste(rebuilt, "home_speed_line_a.png", 28, 318)
    paste(rebuilt, "home_speed_line_b.png", 296, 384)
    paste(rebuilt, "home_speed_line_c.png", 64, 466)
    paste(rebuilt, "home_rider_shadow.png", 121, 510)
    paste(rebuilt, "home_bottom_fade.png", 0, 622)

    diff = ImageChops.difference(old, rebuilt)
    diff = ImageEnhance.Brightness(diff).enhance(8)
    diff = diff.convert("RGBA")
    diff.putalpha(255)

    gap = 12
    header = 34
    w = old.width * 3 + gap * 4
    h = old.height + header + gap
    compare = Image.new("RGBA", (w, h), rgba("#f2f5f7"))
    draw = ImageDraw.Draw(compare)
    f = ImageFont.truetype(str(FONT_BOLD), 16)
    labels = ["完整静帧 home_scene_bg", "静态底图 + 动态层重组", "差异增强 8x"]
    xs = [gap, gap * 2 + old.width, gap * 3 + old.width * 2]
    for label, x in zip(labels, xs):
        draw.text((x, 8), label, fill=rgba("#17212b"), font=f)
    compare.alpha_composite(old, (xs[0], header))
    compare.alpha_composite(rebuilt, (xs[1], header))
    compare.alpha_composite(diff, (xs[2], header))
    compare.save(OUT / "home_dynamic_layers_compare.png")


def compose_reference_compare():
    reference_path = Path(r"C:\Users\11146\AppData\Local\Temp\codex-clipboard-97866e9f-042d-41f7-8c3e-924b40a28af9.png")
    if not reference_path.exists():
        return
    ref = Image.open(reference_path).convert("RGBA")
    preview = Image.open(OUT / "home_layers_preview.png").convert("RGBA")
    target_h = 844

    def fit_height(image):
        ratio = target_h / image.height
        return image.resize((int(round(image.width * ratio)), target_h), Image.Resampling.LANCZOS)

    ref = fit_height(ref)
    preview = fit_height(preview)
    gap = 14
    header = 36
    columns = [ref, preview]
    labels = ["参考截图", "当前拆层重组预览"]
    w = sum(im.width for im in columns) + gap * (len(columns) + 1)
    h = target_h + header + gap
    canvas = Image.new("RGBA", (w, h), rgba("#eef3f6"))
    draw = ImageDraw.Draw(canvas)
    f = ImageFont.truetype(str(FONT_BOLD), 16)
    x = gap
    for label, im in zip(labels, columns):
        draw.text((x, 8), label, fill=rgba("#17212b"), font=f)
        canvas.alpha_composite(im, (x, header))
        x += im.width + gap
    canvas.save(OUT / "home_reference_compare.png")


def crop_reference_screen(image):
    image = image.convert("RGBA")
    if image.size == (454, 961):
        return image.crop((18, 39, 436, 944)).resize((390, 844), Image.Resampling.LANCZOS)

    # The supplied screenshot includes a phone frame. Crop to the bright inner
    # screen so comparisons focus on game UI content.
    px = image.load()
    width, height = image.size
    xs = []
    ys = []
    for y in range(height):
        for x in range(width):
            r, g, b, a = px[x, y]
            if a > 0 and (r > 80 or g > 120 or b > 120):
                xs.append(x)
                ys.append(y)
    if not xs or not ys:
        return image
    left = max(min(xs) - 2, 0)
    top = max(min(ys) - 2, 0)
    right = min(max(xs) + 3, width)
    bottom = min(max(ys) + 3, height)
    cropped = image.crop((left, top, right, bottom))
    return cropped.resize((390, 844), Image.Resampling.LANCZOS)


def compose_reference_screen_compare():
    reference_path = Path(r"C:\Users\11146\AppData\Local\Temp\codex-clipboard-97866e9f-042d-41f7-8c3e-924b40a28af9.png")
    if not reference_path.exists():
        return
    ref = crop_reference_screen(Image.open(reference_path))
    preview = Image.open(OUT / "home_layers_preview.png").convert("RGBA")
    diff = ImageChops.difference(ref, preview)
    diff = ImageEnhance.Brightness(diff).enhance(3)
    diff = diff.convert("RGBA")
    diff.putalpha(255)

    gap = 12
    header = 34
    columns = [ref, preview, diff]
    labels = ["参考截图裁屏", "当前拆层重组", "参考 vs 当前预览 差异 3x"]
    w = 390 * len(columns) + gap * (len(columns) + 1)
    h = 844 + header + gap
    canvas = Image.new("RGBA", (w, h), rgba("#eef3f6"))
    draw = ImageDraw.Draw(canvas)
    f = ImageFont.truetype(str(FONT_BOLD), 16)
    for index, (label, image) in enumerate(zip(labels, columns)):
        x = gap + index * (390 + gap)
        draw.text((x, 8), label, fill=rgba("#17212b"), font=f)
        canvas.alpha_composite(image, (x, header))
    canvas.save(OUT / "home_reference_screen_compare.png")


def compose_html_render_compare():
    html_path = OUT / "home_html_edge_454.png"
    if not html_path.exists():
        return
    html = crop_reference_screen(Image.open(html_path))
    preview = Image.open(OUT / "home_layers_preview.png").convert("RGBA")
    diff = ImageChops.difference(html, preview)
    diff = ImageEnhance.Brightness(diff).enhance(3)
    diff = diff.convert("RGBA")
    diff.putalpha(255)

    gap = 12
    header = 34
    columns = [html, preview, diff]
    labels = ["HTML 浏览器渲染裁屏", "新拆层重组", "HTML vs 拆层 差异 3x"]
    w = 390 * len(columns) + gap * (len(columns) + 1)
    h = 844 + header + gap
    canvas = Image.new("RGBA", (w, h), rgba("#eef3f6"))
    draw = ImageDraw.Draw(canvas)
    f = ImageFont.truetype(str(FONT_BOLD), 16)
    for index, (label, image) in enumerate(zip(labels, columns)):
        x = gap + index * (390 + gap)
        draw.text((x, 8), label, fill=rgba("#17212b"), font=f)
        canvas.alpha_composite(image, (x, header))
    canvas.save(OUT / "home_html_render_compare.png")


def compose_asset_layers_sheet():
    entries = [
        ("静态背景", "home_scene_bg_static.png", (148, 320)),
        ("完整背景", "home_scene_bg.png", (148, 320)),
        ("云 1", "home_cloud_one.png", None),
        ("云 2", "home_cloud_two.png", None),
        ("车道线", "home_lane_strip.png", (36, 220)),
        ("速度线 A", "home_speed_line_a.png", None),
        ("速度线 B", "home_speed_line_b.png", None),
        ("速度线 C", "home_speed_line_c.png", None),
        ("金币底板", "home_coin_badge_base.png", None),
        ("金币图标", "home_coin_icon.png", None),
        ("骑手阴影", "home_rider_shadow.png", None),
        ("底部渐变", "home_bottom_fade.png", (180, 102)),
        ("标题", "home_title.png", (190, 105)),
        ("骑手", "home_rider.png", (150, 150)),
        ("主按钮", "home_start_button_base.png", (260, 64)),
        ("右侧按钮蓝", "home_round_blue.png", None),
        ("底部按钮", "home_dock_button.png", None),
        ("底部图标橙", "home_dock_icon_orange.png", None),
        ("底部图标蓝", "home_dock_icon_blue.png", None),
        ("底部图标绿", "home_dock_icon_green.png", None),
        ("底部图标灰", "home_dock_icon_gray.png", None),
    ]
    cell_w, cell_h = 230, 190
    cols = 4
    rows = (len(entries) + cols - 1) // cols
    canvas = Image.new("RGBA", (cell_w * cols, cell_h * rows), rgba("#eef3f6"))
    draw = ImageDraw.Draw(canvas)
    label_font = ImageFont.truetype(str(FONT_BOLD), 15)

    def draw_checker(x0, y0, x1, y1):
        size = 10
        for y in range(y0, y1, size):
            for x in range(x0, x1, size):
                color = rgba("#d8e1e8") if ((x // size + y // size) % 2 == 0) else rgba("#7f8d98")
                draw.rectangle((x, y, min(x + size, x1), min(y + size, y1)), fill=color)

    def fit_layer_preview(image, max_w, max_h):
        if image.width < 80 and image.height < 80:
            scale = min(4, max_w / image.width, max_h / image.height)
            if scale > 1:
                image = image.resize((int(image.width * scale), int(image.height * scale)), Image.Resampling.NEAREST)
        image.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)
        return image

    for idx, (label, name, target_size) in enumerate(entries):
        col = idx % cols
        row = idx // cols
        x = col * cell_w
        y = row * cell_h
        draw.rectangle((x + 6, y + 6, x + cell_w - 6, y + cell_h - 6), fill=rgba("#ffffff"), outline=rgba("#d5dee6"))
        draw.text((x + 14, y + 12), label, fill=rgba("#17212b"), font=label_font)
        preview_box = (x + 12, y + 42, x + cell_w - 12, y + cell_h - 36)
        draw_checker(*preview_box)
        image = Image.open(OUT / name).convert("RGBA")
        if target_size:
            image.thumbnail(target_size, Image.Resampling.LANCZOS)
        else:
            max_w, max_h = cell_w - 34, cell_h - 54
            image = fit_layer_preview(image, max_w, max_h)
        ix = x + (cell_w - image.width) // 2
        iy = y + 48 + (cell_h - 58 - image.height) // 2
        canvas.alpha_composite(image, (ix, iy))
        draw.text((x + 14, y + cell_h - 28), name, fill=rgba("#607383"), font=ImageFont.truetype(str(FONT_REGULAR), 11))
    canvas.save(OUT / "home_asset_layers_sheet.png")


def main(include_debug=False):
    draw_cloud_one()
    draw_cloud_two()
    draw_lane_strip_frames()
    draw_speed_line("home_speed_line_a.png", 74, 158)
    draw_speed_line("home_speed_line_b.png", 74, 132)
    draw_speed_line("home_speed_line_c.png", 44, 132)
    draw_rider_shadow()
    draw_bottom_fade()
    save_scene_backgrounds(include_debug)
    draw_title()
    draw_subtitle_badge()
    draw_level_badge()
    if include_debug:
        draw_coin_badge()
    draw_coin_badge_base()
    draw_coin_icon()
    draw_xp_assets()
    draw_order_sign()
    draw_rider()
    draw_start_button("home_start_button_base.png")
    draw_start_button("home_start_button_base_pressed.png", pressed=True)
    draw_round_button("home_round_blue.png", "#45c8ff", "#2382df", (16, 61, 112, 86))
    draw_round_button("home_round_green.png", "#36db86", "#1da65d", (12, 93, 49, 86))
    draw_round_button("home_round_red.png", "#ff7373", "#dd3a3a", (119, 22, 22, 86))
    draw_dock_button()
    draw_dock_icon("home_dock_icon_orange.png", "#ff8618")
    draw_dock_icon("home_dock_icon_blue.png", "#2f80ed")
    draw_dock_icon("home_dock_icon_green.png", "#27c96b")
    draw_dock_icon("home_dock_icon_gray.png", "#5b6570")
    if include_debug:
        compose_preview()
        compose_layer_compare()
        compose_reference_compare()
        compose_reference_screen_compare()
        compose_html_render_compare()
        compose_asset_layers_sheet()


def parse_args():
    parser = argparse.ArgumentParser(description="导出首页运行时贴图")
    parser.add_argument(
        "--debug-previews",
        action="store_true",
        help="额外生成完整背景、分层预览和对比检查图；默认不生成调试产物。",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    main(include_debug=args.debug_previews)
