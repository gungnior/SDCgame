#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_comfy.py -- 通过 ComfyUI HTTP API 批量生成像素素材

依据 specs/art-pipeline.md §8：
  §8.1  单资产流程：写 prompt -> 生成 -> 量化 -> 对齐 -> 修帧 -> 补帧 -> 预览
  §8.4  动画帧一致性：**不要**让 AI 一次生成多帧，只出单帧，其余靠脚本补

本脚本做 §8.1 的前半段（生成 + 下采样 + 量化入库到 art/_raw/），
修帧与补帧由美术脚本与人工完成。

前置：ComfyUI 必须已在 127.0.0.1:8188 运行。

用法：
    python tools/art/gen_comfy.py --list-models
    python tools/art/gen_comfy.py --batch b_first          # 跑预设批次
    python tools/art/gen_comfy.py --kind tile --name floor_concrete --n 4
"""

import argparse
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from artlib import ART, SPEC, load_palette, quantize, save_palette_json, ANCHOR_FOOT  # noqa: E402
import postprocess as POST  # noqa: E402

try:
    from PIL import Image
except ImportError:
    raise SystemExit("需要 Pillow")


COMFY = os.environ.get("COMFY_URL", "http://127.0.0.1:8188")
RAW_DIR = ART / "_raw"

# 默认底模：通用 SDXL（动漫微调会和 pixel-art LoRA 打架）
DEFAULT_CKPT = r"sdxl\perfectdeliberate_v10.safetensors"
DEFAULT_LORA = "pixel-art-xl.safetensors"
LORA_STRENGTH = 1.15

# ─────────── 各资产类型的 prompt 模板 ───────────
# 一律用英文（SDXL 对英文最稳）；明确写 "pixel art" + 尺寸感 + 视角

STYLE = ("pixel art sprite, 16-bit, limited palette, muted military colors, "
         "sharp hard edges, no anti-aliasing, no blur, "
         "single subject, centered, isolated on solid magenta background")

# ⚠️ 实测教训：不写死姿态，模型会画成斜俯视/趴姿，没法用。
#    pixel-art-xl 对 "side profile / facing right" 这类约束响应明显。
POSE_CHAR = ("flat 2D side profile view, standing upright, facing right, "
             "full body head to toe, orthographic, no perspective")
POSE_GUN = ("flat 2D side profile, perfectly horizontal, barrel pointing right, "
            "orthographic, no perspective")
POSE_ITEM = ("single object, flat 2D icon, top-down orthographic, centered")
POSE_TILE = ("seamless tileable texture, flat top-down orthographic, uniform lighting")

NEG = ("blurry, smooth gradient, anti-aliasing, 3d render, realistic photo, "
       "text, watermark, signature, ui, border, frame, drop shadow, "
       "multiple subjects, two characters, collage, sprite sheet, grid, "
       "blurred, jpeg artifacts, extra limbs, deformed, perspective, "
       "diagonal, tilted, lying down, prone, dark background")

TEMPLATES = {
    # ── 地形 tile ──
    # ⚠️ 实测：写 "tile" 时 pixel-art-xl 会画成生物（训练集偏角色）。
    #    改成 "seamless texture" 描述材质本身才听话。
    "tile_floor_concrete": f"{POSE_TILE}, weathered grey concrete surface with fine cracks, {STYLE}",
    "tile_floor_asphalt":  f"{POSE_TILE}, dark asphalt road surface with gravel, {STYLE}",
    "tile_floor_dirt":     f"{POSE_TILE}, dry packed dirt ground with small stones, {STYLE}",
    "tile_floor_metal":    f"{POSE_TILE}, industrial steel plate floor with rivets, {STYLE}",
    "tile_wall_concrete":  f"{POSE_TILE}, rough concrete wall surface, stains and chipping, {STYLE}",
    "tile_wall_brick":     f"{POSE_TILE}, damaged red brick wall, mortar lines, {STYLE}",
    "tile_wall_metal":     f"{POSE_TILE}, corrugated rusty metal wall panel, {STYLE}",
    "tile_door_metal":     f"{POSE_ITEM}, closed steel security door, handle and hinges, {STYLE}",
    "tile_crate_wood":     f"{POSE_ITEM}, wooden military supply crate viewed from above, {STYLE}",
    "tile_barrel_rust":    f"{POSE_ITEM}, rusty oil barrel viewed from above, {STYLE}",
    "tile_sandbag":        f"{POSE_ITEM}, sandbag barricade viewed from above, {STYLE}",
    "tile_debris":         f"{POSE_ITEM}, scattered rubble and broken concrete, {STYLE}",

    # ── 角色（单帧！多帧会让 AI 把人画变形 —— art-pipeline §8.4）──
    "char_player_side":    f"{POSE_CHAR}, soldier in tactical vest and helmet carrying an assault rifle, {STYLE}",
    "char_player_front":   f"flat 2D front view, standing upright, full body, soldier in tactical vest, {STYLE}",
    "char_player_back":    f"flat 2D back view, standing upright, full body, soldier with backpack, {STYLE}",
    "char_enemy_scav_side":f"{POSE_CHAR}, ragged scavenger in hooded jacket holding a pistol, {STYLE}",
    "char_enemy_infected_side": f"{POSE_CHAR}, hunched infected mutant with torn clothes, {STYLE}",

    # ── 物品图标 ──
    "item_medical_bandage":    f"{POSE_ITEM}, rolled gauze bandage, {STYLE}",
    "item_medical_kit":        f"{POSE_ITEM}, white first aid kit box with red cross, {STYLE}",
    "item_medical_painkiller": f"{POSE_ITEM}, small pill bottle with white cap, {STYLE}",
    "item_ammo_pistol":        f"{POSE_ITEM}, small stack of brass pistol cartridges, {STYLE}",
    "item_ammo_rifle":         f"{POSE_ITEM}, small stack of rifle cartridges, {STYLE}",
    "item_ammo_shell":         f"{POSE_ITEM}, red shotgun shells, {STYLE}",
    "item_armor_light":        f"{POSE_ITEM}, light black tactical vest, {STYLE}",
    "item_armor_heavy":        f"{POSE_ITEM}, heavy armored plate carrier with pouches, {STYLE}",
    "item_backpack_tactical":  f"{POSE_ITEM}, olive military backpack, {STYLE}",
    "item_consumable_can":     f"{POSE_ITEM}, dented canned food tin, {STYLE}",
    "item_consumable_water":   f"{POSE_ITEM}, clear plastic water bottle, {STYLE}",
    "item_valuables_goldwatch":f"{POSE_ITEM}, gold wristwatch, {STYLE}",
    "item_valuables_gpu":      f"{POSE_ITEM}, computer graphics card with fan, {STYLE}",
    "item_valuables_hdd":      f"{POSE_ITEM}, rugged military hard drive, {STYLE}",
    "item_key_labcard":        f"{POSE_ITEM}, plastic keycard with barcode stripe, {STYLE}",

    # ── 枪械底图 ──
    "gun_weapon_pistol":  f"{POSE_GUN}, compact semi-automatic pistol, {STYLE}",
    "gun_weapon_rifle":   f"{POSE_GUN}, assault rifle with magazine and optic, {STYLE}",
    "gun_weapon_shotgun": f"{POSE_GUN}, pump action shotgun, {STYLE}",
}

# 每种类型的目标画布尺寸（来自 artlib.SPEC）
KIND_SIZE = {
    "tile": SPEC["tile"],
    "item": SPEC["item_icon"],
    "char": SPEC["character_frame"],
    "gun": SPEC["gun_base"],
}


def kind_of(name: str) -> str:
    if name.startswith("tile_"):
        return "tile"
    if name.startswith("item_"):
        return "item"
    if name.startswith("char_"):
        return "char"
    if name.startswith("gun_"):
        return "gun"
    return "item"


# ─────────── ComfyUI HTTP API ───────────

def api(path, payload=None, timeout=30):
    url = f"{COMFY}{path}"
    if payload is None:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def list_models():
    info = api("/object_info")
    ckpts = info.get("CheckpointLoaderSimple", {}).get("input", {}).get("required", {})
    ckpt_list = ckpts.get("ckpt_name", [[]])[0]
    loras = info.get("LoraLoader", {}).get("input", {}).get("required", {})
    lora_list = loras.get("lora_name", [[]])[0]
    return ckpt_list, lora_list


def build_workflow(prompt, negative, ckpt, lora, seed, size=768, steps=30, cfg=7.0, lora_strength=None):
    return {
        "1": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": ckpt}},
        "2": {"class_type": "LoraLoader",
              "inputs": {"model": ["1", 0], "clip": ["1", 1],
                         "lora_name": lora, "strength_model": LORA_STRENGTH,
                         "strength_clip": LORA_STRENGTH}},
        "3": {"class_type": "CLIPTextEncode",
              "inputs": {"text": prompt, "clip": ["2", 1]}},
        "4": {"class_type": "CLIPTextEncode",
              "inputs": {"text": negative, "clip": ["2", 1]}},
        "5": {"class_type": "EmptyLatentImage",
              "inputs": {"width": size, "height": size, "batch_size": 1}},
        "6": {"class_type": "KSampler",
              "inputs": {"model": ["2", 0], "positive": ["3", 0], "negative": ["4", 0],
                         "latent_image": ["5", 0], "seed": seed, "steps": steps,
                         "cfg": cfg, "sampler_name": "dpmpp_2m",
                         "scheduler": "karras", "denoise": 1.0}},
        "7": {"class_type": "VAEDecode",
              "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage",
              "inputs": {"images": ["7", 0], "filename_prefix": "gen"}},
    }


def generate_one(name, template, ckpt, lora, seed, size, steps, out_dir):
    wf = build_workflow(template, NEG, ckpt, lora, seed, size=size, steps=steps)
    res = api("/prompt", {"prompt": wf})
    pid = res.get("prompt_id")
    if not pid:
        return None, f"提交失败: {res}"

    # 轮询
    for _ in range(600):
        time.sleep(0.5)
        hist = api(f"/history/{pid}")
        if pid in hist:
            entry = hist[pid]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                return None, f"生成错误: {status}"
            for node_id, out in entry.get("outputs", {}).items():
                for img in out.get("images", []):
                    src = Path(out.get("__dir__", "")) if out.get("__dir__") else None
                    fn = img.get("filename")
                    sub = img.get("subfolder", "")
                    return fetch_image(fn, sub, out_dir, name), None
            return None, "没有输出图像"
    return None, "超时"


def fetch_image(filename, subfolder, out_dir, name):
    """从 ComfyUI 的 /view 端点取图，落盘到 _raw/"""
    from urllib.parse import quote
    url = f"{COMFY}/view?filename={quote(filename)}&subfolder={quote(subfolder)}&type=output"
    out_dir.mkdir(parents=True, exist_ok=True)
    # 保留原始文件名便于溯源
    raw_path = out_dir / f"{name}_{filename}"
    with urllib.request.urlopen(url, timeout=60) as r:
        raw_path.write_bytes(r.read())
    return raw_path


def postprocess(raw_path, name, kind, palette, tol=38, dither=False):
    """
    完整后处理：去背景 -> 裁主体 -> 缩放对齐锚点 -> 量化。
    art-pipeline §8.1 的 ③④⑤ 步。

    ⚠️ 实测：不做这些直接压到目标尺寸会又小又糊 ——
       主体在 768x768 里只占一小块，背景也不透明。
    """
    target = KIND_SIZE.get(kind, (32, 32))
    if kind == "char":
        scale_mode = "fit"
        anchor = ANCHOR_FOOT
    elif kind == "gun":
        scale_mode = "fit"          # 细长物体，保持比例
        anchor = None
    elif kind == "tile":
        scale_mode = "fill"         # 贴图铺满，不留透明边
        anchor = None
    else:
        scale_mode = "fit"
        anchor = None

    img = POST.process(raw_path, target, anchor=anchor, palette=palette,
                       tolerance=tol, scale_mode=scale_mode, pad=2)
    return img, target


# ─────────── 批次 ───────────

BATCHES = {
    "b_first": [
        # 第一批：足够把画面从"几何图形"变成"像游戏"
        "tile_floor_concrete", "tile_floor_dirt", "tile_wall_concrete",
        "tile_crate_wood", "tile_barrel_rust",
        "char_player_side", "char_enemy_scav_side", "char_enemy_infected_side",
        "item_medical_kit", "item_ammo_rifle", "item_backpack_tactical",
        "gun_weapon_rifle",
    ],
    "b_tiles": [k for k in TEMPLATES if k.startswith("tile_")],
    "b_items": [k for k in TEMPLATES if k.startswith("item_")],
    "b_chars": [k for k in TEMPLATES if k.startswith("char_")],
    "b_guns":  [k for k in TEMPLATES if k.startswith("gun_")],
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list-models", action="store_true")
    ap.add_argument("--batch")
    ap.add_argument("--kind")
    ap.add_argument("--name")
    ap.add_argument("--n", type=int, default=1, help="每个资产生成几张（挑最好的）")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--ckpt", default=DEFAULT_CKPT)
    ap.add_argument("--lora", default=DEFAULT_LORA)
    ap.add_argument("--size", type=int, default=768)
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--lora-strength", type=float, default=None)
    ap.add_argument("--out", default="")
    ap.add_argument("--no-post", action="store_true", help="只出原图，不做下采样+量化")
    args = ap.parse_args()

    if args.list_models:
        ck, lo = list_models()
        print("可用 checkpoints:")
        for c in ck:
            print("  ", c)
        print("可用 LoRA:")
        for l in lo:
            mark = "  <-- 像素画" if "pixel" in l.lower() else ""
            print("  ", l, mark)
        return 0

    names = []
    if args.batch:
        names = BATCHES.get(args.batch, [])
        if not names:
            print(f"未知批次：{args.batch}，可选：{list(BATCHES)}")
            return 1
    elif args.kind and args.name:
        names = [f"{args.kind}_{args.name}"]
    elif args.name:
        names = [args.name]
    else:
        print("需要 --batch 或 (--kind + --name) 或 --name")
        return 1

    palette = load_palette()
    save_palette_json()
    out_dir = Path(args.out) if args.out else (ART / "_raw")
    ok = 0
    fail = 0
    t0 = time.time()

    for name in names:
        tpl = TEMPLATES.get(name)
        if not tpl:
            print(f"  [跳过] 没有模板：{name}")
            continue
        kind = kind_of(name)
        for i in range(args.n):
            seed = args.seed + i if args.seed else random.randint(1, 2**31 - 1)
            print(f"  [{name}] #{i+1}/{args.n} seed={seed} ...", flush=True)
            raw, err = generate_one(name, tpl, args.ckpt, args.lora, seed,
                                    args.size, args.steps, out_dir)
            if err:
                print(f"    ❌ {err}")
                fail += 1
                continue
            if args.no_post:
                print(f"    ✅ 原图 {raw.name}")
                ok += 1
                continue
            img, target = postprocess(raw, name, kind, palette)
            final = ART / "gen" / f"{name}_{seed}.png"
            final.parent.mkdir(parents=True, exist_ok=True)
            img.save(final)
            print(f"    ✅ {target[0]}x{target[1]} -> {final.relative_to(ART.parent)}")
            ok += 1

    print(f"\n完成：成功 {ok}，失败 {fail}，耗时 {time.time()-t0:.0f} 秒")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
