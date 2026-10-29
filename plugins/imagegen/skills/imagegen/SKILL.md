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

```bash
# New image
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/hero.png \
  "Wide 16:9 hero illustration of a cozy coffee shop at dusk, warm lighting, flat vector style"

# Game sprite with transparent background
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/coin.png --transparent \
  "Single gold coin game sprite, 3/4 view, soft shading, centered, no shadow"

# Edit an existing image
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out assets/hero-night.png --input assets/hero.png \
  "Change the scene to night with neon signs; keep the layout, characters and camera angle identical"

# Three variants
${CLAUDE_SKILL_DIR}/scripts/codex-imagegen.sh --out logo-ideas.png --n 3 \
  "Minimal mascot logo of a piggy bank, flat colors, white background"
```

## Troubleshooting

- `codex CLI not found`: install Codex CLI and log in.
- `no new image was found`: read the Codex log on stderr; usually the account lacks image generation access or the request was refused. Check `codex features list | grep image_generation` shows `true`.
