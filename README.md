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

## Update

```bash
claude plugin marketplace update codex-imagegen
claude plugin update imagegen@codex-imagegen
```
