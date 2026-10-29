---
name: imagegen
description: Generate or edit raster images (photos, illustrations, sprites, game assets, textures, icons as bitmaps, UI mockups, transparent cutouts) by delegating to Codex CLI's built-in image_gen tool. Use when the user asks to generate, create, draw, or edit an image/picture/gambar, or when a task needs an AI-made bitmap asset. Do not use when the visual is better built directly as SVG, HTML/CSS, or canvas code.
---

# Image generation via Codex CLI

Claude cannot generate images itself, so this skill calls `codex exec` (OpenAI Codex CLI), whose built-in `image_gen` tool makes the image. The wrapper script copies the result to the path you choose.

Requirements: `codex` on PATH and logged in (`codex login`). No `OPENAI_API_KEY` needed.

## Command

```bash
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out <path.png> [options] "<prompt>"
```

Options:
- `--out <path>`: where to save (required). Use the project's asset folder when the image is for the project, otherwise the current directory.
- `--input <img>`: attach an image as an edit target or a reference. Repeatable.
- `--n <count>`: number of variants; saved as `<name>-1.png`, `<name>-2.png`, ...
- `--transparent`: transparent background.
- `--region x,y,w,h`: lock everything outside this rectangle to the original (the first `--input`). Pixels or fractions 0–1 of width/height. Repeatable.
- `--mask <png>`: same, with a grayscale mask instead (white = editable, black = locked).
- `--feather <px>`: soft blend width inside the region edge (default 1% of the shorter side).
- `--diff <png>`: also save a difference heatmap of the result vs the original, with the region outlined in red.

The script prints the saved path(s) on stdout. Each image takes roughly 30–60 seconds, so run it with a Bash timeout of at least 300000 ms (more for several variants), or in the background for big batches.

## Workflow

1. Turn the user's request into a clear prompt. Keep it faithful: if they were specific, just structure it; if vague, add only helpful framing (composition, style, lighting, intended use, aspect ratio). Do not add objects, brands or text they didn't ask for. Quote any exact text that must appear in the image.
2. Choose an output path. Never overwrite an existing file unless asked; use a versioned name like `hero-v2.png`.
3. For edits, pass the source with `--input` and say in the prompt what to change and what to keep identical. If the rest of the image must stay unchanged, use a region-locked edit (see below).
4. For several distinct assets, run the script once per asset (each with its own prompt). Use `--n` only for variants of one prompt.
5. After it finishes, open the result with the Read tool to check it matches the request (subject, style, text, background). If something is wrong, adjust the prompt with one targeted change and run again.
6. Report the saved path(s) and the prompt used.

## Region-locked edits

Codex image_gen never edits in place: it re-renders the whole image, so even with "keep everything identical" the colors, lines, position and sometimes the size drift everywhere. When only part of an image may change:

1. Get the original's size (`sips -g pixelWidth -g pixelHeight img.png` on macOS, or `file img.png`) and look at it with Read.
2. Pick the editable rectangle in the original's pixels. Be generous: include room for the new content (a hat needs space above the head) plus a margin, since the model may shift things slightly.
3. Run the edit with `--input <original> --region x,y,w,h` (or `--mask`). The script composites the generated region onto the original and prints a report on stderr:
   - `inside editable region: N% changed`: near 0% means the edit didn't land in the region; move or enlarge it.
   - `outside editable region: N% changed`: how much the raw generation drifted (informational; it is discarded).
   - `final: outside region identical to original: yes`: the guarantee. Anything else is an error to report.
4. Open the result with Read and check the seam around the region. If the new content is cut off at the region edge or misaligned with the original, enlarge the region and run again. Pass `--diff` for a heatmap when you need to see exactly what changed.

To verify any edit after the fact (for example one made without a region), compare it with the original:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/edit_tools.py compare --original a.png --edited b.png \
  [--region x,y,w,h] [--diff diff.png]
```

Use `uv run --no-project --with pillow python` in place of `python3` when Pillow isn't installed. A pixel-by-pixel equality check of a raw image_gen edit will always fail; that is expected, and the reason to use regions.

## Examples

Paths and subjects below are placeholders; adapt them to the user's project.

```bash
# Illustration for a website or document
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out images/banner.png \
  "Wide 16:9 illustration of a mountain landscape at sunrise, soft gradients, flat vector style, no text"

# Photorealistic image
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out images/product.png \
  "Studio product photo of a ceramic mug on a light gray background, soft diffused light, square 1:1"

# Asset with transparent background (sprite, icon, sticker)
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/star.png --transparent \
  "Single yellow star icon, slight 3D shading, centered, no shadow"

# Seamless texture
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/wood.png \
  "Seamless tileable oak wood texture, top-down, even lighting, square"

# Edit an existing image
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out images/banner-night.png --input images/banner.png \
  "Change the scene to night with a starry sky; keep the composition, colors of the foreground and style identical"

# Change only one part; everything outside the region stays pixel-identical
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out images/portrait-glasses.png --input images/portrait.png \
  --region 300,180,420,200 --diff images/portrait-glasses.diff.png \
  "Add round black glasses to the person; keep the face, pose, framing and image size exactly the same"

# New image that follows a reference's style
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/tree.png --transparent --input assets/star.png \
  "A small round tree in the same art style, shading and outline weight as the attached image"

# Several variants of one prompt
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out logo-ideas.png --n 3 \
  "Minimal logo mark of a paper plane, two flat colors, white background, no text"
```

### Game assets

```bash
# Character sprite
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/sprites/knight.png --transparent \
  "2D side-view game character: a small knight with a blue cape, idle pose, full body, centered, cartoon style, clean outline, no shadow"

# Matching enemy, using the character as a style reference
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/sprites/slime.png --transparent \
  --input assets/sprites/knight.png \
  "A green slime enemy in the same art style, outline weight, palette and scale as the attached character, full body, centered"

# Collectible / item icons
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/items/potion.png --transparent \
  "Inventory icon of a red health potion bottle, 3/4 view, bold outline, centered, fills most of the frame"

# Pixel art
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/sprites/chest.png --transparent \
  "Pixel art treasure chest, 32x32 style with large visible pixels, limited 16-color palette, no anti-aliasing, centered"

# Animation frames as a sprite sheet
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/sprites/knight-walk.png --transparent \
  --input assets/sprites/knight.png \
  "Sprite sheet of the attached character walking: 4 frames in one horizontal row, equal spacing, same size and facing right in every frame"

# Tileable terrain tile
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/tiles/grass.png \
  "Seamless tileable top-down grass tile for a 2D game, stylized, even lighting, square, edges match on all sides"

# Level background (parallax layer)
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/backgrounds/forest-far.png \
  "Wide 16:9 side-scroller background layer: distant forest silhouettes and hills, muted colors, low detail, no characters, horizontally tileable"

# UI elements
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/ui/button.png --transparent \
  "Game UI button, wide rounded rectangle, wooden frame with a gold border, empty center for text, no text, front view"
```

Tips for game assets:
- Make the first key asset (main character or one item), then pass it with `--input` for every later asset so the style, palette and scale stay consistent.
- Use `--transparent` for sprites, items and UI. Leave it off for backgrounds and tiles.
- Ask for no text in UI art; the game renders its own labels.
- Generated sprite sheets and pixel art are approximate: frame spacing and pixel grids may not be exact. Check them with Read, and tell the user when they need slicing, resizing (nearest-neighbor for pixel art) or cleanup in an editor.

## Troubleshooting

- `codex CLI not found`: install Codex CLI and log in.
- `need Pillow ... or uv`: region-locked edits need `python3 -m pip install pillow` or [uv](https://docs.astral.sh/uv/) on PATH.
- `no new image was found`: read the Codex log on stderr; usually the account lacks image generation access or the request was refused. Check `codex features list | grep image_generation` shows `true`.
