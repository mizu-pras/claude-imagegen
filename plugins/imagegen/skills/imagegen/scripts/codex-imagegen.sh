#!/usr/bin/env bash
# Generate or edit raster images by delegating to Codex CLI's built-in image_gen tool.
#
# Usage:
#   codex-imagegen.sh --out <path.png> [--input <img>]... [--n <count>] [--transparent] [--] "<prompt>"
#
# --out          Destination file. With --n > 1, files are saved as <name>-1.png, <name>-2.png, ...
# --input        Image to attach (edit target or style/composition reference). Repeatable.
# --n            Number of variants (default 1).
# --transparent  Ask for a transparent background (alpha preserved).
#
# Prints the saved file path(s), one per line, on stdout. Codex logs go to stderr.

set -euo pipefail

out=""
n=1
transparent=0
inputs=()
prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --input) inputs+=("$2"); shift 2 ;;
    --n) n="$2"; shift 2 ;;
    --transparent) transparent=1; shift ;;
    --) shift; prompt="$*"; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) prompt="$*"; break ;;
  esac
done

if [[ -z "$prompt" || -z "$out" ]]; then
  echo "Usage: $0 --out <path.png> [--input <img>]... [--n <count>] [--transparent] \"<prompt>\"" >&2
  exit 2
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found on PATH. Install it and run 'codex login' first." >&2
  exit 1
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
gen_dir="$codex_home/generated_images"
mkdir -p "$gen_dir" "$(dirname "$out")"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
marker="$workdir/.marker"
touch "$marker"

image_args=()
for img in "${inputs[@]+"${inputs[@]}"}"; do
  [[ -f "$img" ]] || { echo "Input image not found: $img" >&2; exit 1; }
  image_args+=(-i "$img")
done

instructions="Use your built-in image_gen tool. Do not use the CLI fallback, do not write files, and do not run shell commands."
if [[ ${#inputs[@]} -gt 0 ]]; then
  instructions+=" The attached image(s) are already in context: edit them or use them as references, as the request below says."
fi
if [[ "$n" -gt 1 ]]; then
  instructions+=" Generate exactly $n separate images (one image_gen call each) as variants of the request."
else
  instructions+=" Generate exactly one image."
fi
if [[ "$transparent" -eq 1 ]]; then
  instructions+=" The image must have a genuinely transparent background; preserve the alpha channel."
fi
instructions+=" When finished, reply with just DONE.

Request:
$prompt"

log="$workdir/codex.log"
if ! codex exec --skip-git-repo-check -s read-only -C "$workdir" \
     "${image_args[@]+"${image_args[@]}"}" -- "$instructions" >"$log" 2>&1; then
  cat "$log" >&2
  echo "codex exec failed." >&2
  exit 1
fi
cat "$log" >&2

session_id="$(grep -m1 -E '^session id:' "$log" | awk '{print $3}' || true)"
if [[ -n "$session_id" && -d "$gen_dir/$session_id" ]]; then
  search_dir="$gen_dir/$session_id"
else
  search_dir="$gen_dir"
fi

results=()
while IFS= read -r f; do results+=("$f"); done < <(
  find "$search_dir" -type f -newer "$marker" \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) -print0 \
    | xargs -0 ls -tr 2>/dev/null
)

if [[ ${#results[@]} -eq 0 ]]; then
  echo "Codex finished but no new image was found in $search_dir." >&2
  exit 1
fi

base="${out%.*}"
ext="${out##*.}"
[[ "$ext" == "$out" ]] && ext="png"

if [[ ${#results[@]} -eq 1 ]]; then
  cp "${results[0]}" "$out"
  echo "$out"
else
  i=1
  for f in "${results[@]}"; do
    dest="$base-$i.$ext"
    cp "$f" "$dest"
    echo "$dest"
    i=$((i + 1))
  done
fi
