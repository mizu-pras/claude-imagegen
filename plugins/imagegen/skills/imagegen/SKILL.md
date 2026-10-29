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

The script prints the saved path(s) on stdout. Each image takes roughly 30–60 seconds, so run it with a Bash timeout of at least 300000 ms (more for several variants), or in the background for big batches.

## Workflow

1. Turn the user's request into a clear prompt. Keep it faithful: if they were specific, just structure it; if vague, add only helpful framing (composition, style, lighting, intended use, aspect ratio). Do not add objects, brands or text they didn't ask for. Quote any exact text that must appear in the image.
2. Choose an output path. Never overwrite an existing file unless asked; use a versioned name like `hero-v2.png`.
3. For edits, pass the source with `--input` and say in the prompt what to change and what to keep identical.
4. For several distinct assets, run the script once per asset (each with its own prompt). Use `--n` only for variants of one prompt.
5. After it finishes, open the result with the Read tool to check it matches the request (subject, style, text, background). If something is wrong, adjust the prompt with one targeted change and run again.
6. Report the saved path(s) and the prompt used.

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

# New image that follows a reference's style
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/tree.png --transparent --input assets/star.png \
  "A small round tree in the same art style, shading and outline weight as the attached image"

# Several variants of one prompt
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out logo-ideas.png --n 3 \
  "Minimal logo mark of a paper plane, two flat colors, white background, no text"
```

## Troubleshooting

- `codex CLI not found`: install Codex CLI and log in.
- `no new image was found`: read the Codex log on stderr; usually the account lacks image generation access or the request was refused. Check `codex features list | grep image_generation` shows `true`.
