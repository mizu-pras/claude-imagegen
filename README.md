# claude-imagegen

Claude Code plugin that generates and edits images by calling [Codex CLI](https://github.com/openai/codex)'s built-in `image_gen` tool.

## Requirements (on every device)

- Claude Code running locally (not a cloud session)
- Codex CLI installed and logged in: `codex login`

## Install

In Claude Code:

```
/plugin marketplace add mizu-pras/claude-imagegen
/plugin install imagegen@codex-imagegen
```

Or from a terminal:

```bash
claude plugin marketplace add mizu-pras/claude-imagegen
claude plugin install imagegen@codex-imagegen
```

Restart Claude Code after installing.

## Use

Ask for an image ("buatkan gambar sprite koin emas transparan di assets/coin.png") or run `/imagegen:imagegen`.

The skill runs `skills/imagegen/scripts/codex-imagegen.sh`:

```bash
codex-imagegen.sh --out <path.png> [--input <img>]... [--n <count>] [--transparent] "<prompt>"
```

### Edit only part of an image

Codex re-renders the whole image on every edit, so areas you didn't ask to change drift. Pass `--region x,y,w,h` (or `--mask <png>`) with `--input <original>` and the script copies everything outside that area back from the original, so it stays pixel-identical, then prints a report of what changed. `--diff <png>` saves a difference heatmap. This needs Pillow (`python3 -m pip install pillow`) or [uv](https://docs.astral.sh/uv/).

```bash
codex-imagegen.sh --out hat.png --input original.png --region 280,10,380,220 "Add a red pirate hat"
```

## Update

```bash
claude plugin marketplace update codex-imagegen
claude plugin update imagegen@codex-imagegen
```
