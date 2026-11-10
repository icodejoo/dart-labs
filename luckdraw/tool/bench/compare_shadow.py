"""只用 Python 标准库比较真机 PNG，输出阴影 ROI 差异、扫描线和差异图。"""

import argparse
import csv
import json
import struct
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
CHANNEL_LIMIT = 32
DARKNESS_LIMIT = 2
MAX_CHANNEL = 255
FILL_RGB = (68, 136, 204)


def read_png(path):
    """解码无交错的 8 位 RGB/RGBA PNG；拒绝其它格式，避免悄悄误算。"""
    data = Path(path).read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError(f"不是 PNG: {path}")
    offset, compressed = len(PNG_SIGNATURE), bytearray()
    width = height = channels = None
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        chunk = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(kind + chunk) & 0xFFFFFFFF != crc:
            raise ValueError("PNG CRC 错误")
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6) or compression or filtering or interlace:
                raise ValueError("仅支持无交错 8 位 RGB/RGBA")
            channels = 3 if color == 2 else 4
        elif kind == b"IDAT":
            compressed.extend(chunk)
        offset += length + 12
    stride = width * channels
    raw = zlib.decompress(compressed)
    if len(raw) != height * (stride + 1):
        raise ValueError("PNG 行数据长度不符")
    rgba = bytearray()
    previous = bytearray(stride)
    for row_index in range(height):
        start = row_index * (stride + 1)
        filter_type = raw[start]
        row = bytearray(raw[start + 1:start + stride + 1])
        for x in range(stride):
            left = row[x - channels] if x >= channels else 0
            above = previous[x]
            upper_left = previous[x - channels] if x >= channels else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                estimate = left + above - upper_left
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
            else:
                raise ValueError("未知 PNG 行过滤器")
            row[x] = (row[x] + predictor) & MAX_CHANNEL
        if channels == 4:
            rgba.extend(row)
        else:
            for x in range(0, stride, channels):
                rgba.extend(row[x:x + channels])
                rgba.append(MAX_CHANNEL)
        previous = row
    return width, height, rgba


def write_png(path, width, height, rgba):
    """将 RGBA 缓冲区无损压缩保存为 PNG。"""
    def chunk(kind, content):
        """生成带 CRC 的 PNG 块。"""
        return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content) & 0xFFFFFFFF)

    stride = width * 4
    scanlines = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(height))
    Path(path).write_bytes(PNG_SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))


def pixel(data, width, x, y):
    """返回物理像素的 RGBA 四通道。"""
    start = (y * width + x) * 4
    return tuple(data[start:start + 4])


def is_fill(value):
    """识别标准蓝色填充内部，将其从阴影统计中排除。"""
    return max(abs(a - b) for a, b in zip(value[:3], FILL_RGB)) <= DARKNESS_LIMIT


def darkness(value):
    """返回相对白底的 Rec.709 亮度衰减，单位 8 位通道。"""
    return MAX_CHANNEL - sum(a * b for a, b in zip(value, (0.2126, 0.7152, 0.0722)))


def compare(skia, impeller, metadata, output):
    """按设备端 ROI 比较；阈值 32，输出逐行 RGBA CSV 和定量 JSON。"""
    width, height, first = read_png(skia)
    other_width, other_height, second = read_png(impeller)
    if (width, height) != (other_width, other_height):
        raise ValueError("两后端截图尺寸不同")
    info = json.loads(Path(metadata).read_text(encoding="utf-8"))
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    diff = bytearray([0, 0, 0, MAX_CHANNEL]) * (width * height)
    result = {"channel_threshold": CHANNEL_LIMIT, "radius_darkness_threshold": DARKNESS_LIMIT, "width": width, "height": height, "panels": {}}
    curves = []
    for name, roi in info["panels"].items():
        left, top = round(roi["left"]), round(roi["top"])
        right, bottom = left + round(roi["width"]), top + round(roi["height"])
        if not (0 <= left < right <= width and 0 <= top < bottom <= height):
            raise ValueError(f"ROI 越界: {name}")
        total = changed = shadow_total = shadow_changed = error = shadow_error = 0
        filled = []
        for y in range(top, bottom):
            for x in range(left, right):
                a, b = pixel(first, width, x, y), pixel(second, width, x, y)
                delta = [abs(av - bv) for av, bv in zip(a, b)]
                threshold_exceeded = max(delta) > CHANNEL_LIMIT
                total += 1
                changed += threshold_exceeded
                error += sum(delta)
                if is_fill(a):
                    filled.append((x, y))
                shadow = not is_fill(a) and not is_fill(b) and max(darkness(a), darkness(b)) >= DARKNESS_LIMIT
                if shadow:
                    shadow_total += 1
                    shadow_changed += threshold_exceeded
                    shadow_error += sum(delta)
                start = (y * width + x) * 4
                diff[start:start + 4] = bytes([min(MAX_CHANNEL, v * 4) for v in delta[:3]] + [MAX_CHANNEL])
        panel = {"roi_pixels": total, "different_pixels_gt32": changed, "different_ratio": changed / total, "mae_rgba": error / (total * 4), "shadow_pixels": shadow_total, "shadow_different_pixels_gt32": shadow_changed, "shadow_different_ratio": shadow_changed / shadow_total if shadow_total else None, "shadow_mae_rgba": shadow_error / (shadow_total * 4) if shadow_total else None}
        if not filled or (shadow_total == 0 and name != "slot"):
            raise ValueError(f"没有有效填充或阴影: {name}")
        panel["shadow_observable"] = shadow_total > 0
        if shadow_total == 0:
            panel["limitation"] = "老虎机格子填满滚轮视口，外扩阴影被 clipRect 裁剪；本面板仅比较填充，不能判断阴影一致性"
        if name.startswith(("device_", "logical_")):
            scan_y = (min(y for _, y in filled) + max(y for _, y in filled)) // 2
            bounds = [x for x in range(left, right) if is_fill(pixel(first, width, x, scan_y))]
            fill_left, fill_right = min(bounds), max(bounds)
            profiles = []
            for data in (first, second):
                outside = [(x, darkness(pixel(data, width, x, scan_y))) for x in range(left, right) if x < fill_left or x > fill_right]
                visible = [x for x, value in outside if value >= DARKNESS_LIMIT]
                profiles.append({"left_radius_px": fill_left - min(visible) if visible else 0, "right_radius_px": max(visible) - fill_right if visible else 0, "peak_darkness": max(value for _, value in outside)})
            panel["scanline"] = {"physical_y": scan_y, "fill_left": fill_left, "fill_right": fill_right, "skia": profiles[0], "impeller": profiles[1], "radius_delta_px": max(abs(profiles[0][key] - profiles[1][key]) for key in ("left_radius_px", "right_radius_px")), "peak_darkness_delta": abs(profiles[0]["peak_darkness"] - profiles[1]["peak_darkness"])}
            with (output / f"scanline_{name}.csv").open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream, lineterminator="\n")
                writer.writerow(["physical_x", "physical_y", "skia_r", "skia_g", "skia_b", "skia_a", "impeller_r", "impeller_g", "impeller_b", "impeller_a", "skia_darkness", "impeller_darkness"])
                for x in range(left, right):
                    a, b = pixel(first, width, x, scan_y), pixel(second, width, x, scan_y)
                    writer.writerow([x, scan_y, *a, *b, darkness(a), darkness(b)])
            curves.append((name, left, right, scan_y))
        result["panels"][name] = panel
    write_png(output / "shadow_diff.png", width, height, diff)
    (output / "shadow_comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="760" viewBox="0 0 1000 760">', '<rect width="1000" height="760" fill="white"/>', '<text x="40" y="24" font-family="sans-serif" font-size="16">RGBA scanline: Skia solid / Impeller dashed; physical x; channels 0..255</text>']
    for index, (name, left, right, scan_y) in enumerate(curves):
        chart_top = 60 + index * 175
        svg.append(f'<text x="40" y="{chart_top - 8}" font-family="sans-serif" font-size="14">{name}; y={scan_y}; x={left}..{right - 1}</text>')
        svg.append(f'<rect x="40" y="{chart_top}" width="920" height="140" fill="none" stroke="#aaa"/>')
        for data, dashed in ((first, False), (second, True)):
            for channel, color in enumerate(("#d33", "#18933c", "#2672d4", "#888")):
                points = ' '.join(f'{40 + (x - left) * 920 / (right - left - 1):.2f},{chart_top + (MAX_CHANNEL - pixel(data, width, x, scan_y)[channel]) * 140 / MAX_CHANNEL:.2f}' for x in range(left, right))
                dash = ' stroke-dasharray="5 4"' if dashed else ''
                svg.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="1"{dash}/>')
    svg.append('</svg>')
    (output / "shadow_profiles.svg").write_text('\n'.join(svg) + '\n', encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


def main():
    """解析输入路径；两后端须为同一标准场景、同一 DPR 和布局。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skia", required=True)
    parser.add_argument("--impeller", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    compare(args.skia, args.impeller, args.metadata, args.output)


if __name__ == "__main__":
    main()
