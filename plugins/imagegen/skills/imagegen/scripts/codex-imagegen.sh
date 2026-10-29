#!/usr/bin/env bash
# Generate or edit raster images by delegating to Codex CLI's built-in image_gen tool.
#
# Usage:
#   codex-imagegen.sh --out <path.png> [--input <img>]... [--n <count>] [--transparent]
#                     [--region x,y,w,h]... [--mask <png>] [--feather <px>] [--diff <path.png>] [--] "<prompt>"
#
# --out          Destination file. With --n > 1, files are saved as <name>-1.png, <name>-2.png, ...
# --input        Image to attach (edit target or style/composition reference). Repeatable.
# --n            Number of variants (default 1).
# --transparent  Ask for a transparent background (alpha preserved).
#
# Region-locked edits (the first --input is the original):
# --region       Editable rectangle in original pixels, or fractions 0-1 of width/height. Repeatable.
# --mask         Grayscale PNG, white = editable, black = locked.
# --feather      Soft blend width inside the region edge (default: 1% of the shorter side).
# --diff         Also write a difference heatmap (result vs original) to this path.
# Everything outside the region is copied back from the original, so it stays pixel-identical.
# Needs Pillow (python3 -m pip install pillow) or uv on PATH.
#
# Prints the saved file path(s), one per line, on stdout. Codex logs go to stderr.

set -euo pipefail

out=""
n=1
transparent=0
inputs=()
regions=()
mask=""
feather=""
diff=""
prompt=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --input) inputs+=("$2"); shift 2 ;;
    --n) n="$2"; shift 2 ;;
    --transparent) transparent=1; shift ;;
    --region) regions+=("$2"); shift 2 ;;
    --mask) mask="$2"; shift 2 ;;
    --feather) feather="$2"; shift 2 ;;
    --diff) diff="$2"; shift 2 ;;
    --) shift; prompt="$*"; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) prompt="$*"; break ;;
  esac
done

if [[ -z "$prompt" || -z "$out" ]]; then
  echo "Usage: $0 --out <path.png> [--input <img>]... [--n <count>] [--transparent] [--region x,y,w,h]... [--mask <png>] [--feather <px>] [--diff <png>] \"<prompt>\"" >&2
  exit 2
fi

lock=0
if [[ ${#regions[@]} -gt 0 || -n "$mask" ]]; then
  lock=1
  if [[ ${#inputs[@]} -eq 0 ]]; then
    echo "--region/--mask need --input <original image> (the first --input is the original)." >&2
    exit 2
  fi
  if [[ -n "$mask" && ! -f "$mask" ]]; then
    echo "Mask not found: $mask" >&2
    exit 1
  fi
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if python3 -c 'import PIL' >/dev/null 2>&1; then
    py=(python3)
  elif command -v uv >/dev/null 2>&1; then
    py=(uv run --quiet --no-project --with pillow python)
  else
    echo "Region-locked edits need Pillow (python3 -m pip install pillow) or uv on PATH." >&2
    exit 1
  fi
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
if [[ "$lock" -eq 1 ]]; then
  instructions+=" Keep the first attached image's framing, size, subject position and scale exactly the same; change only what the request asks for."
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

# Copy one generated image to its destination; for region-locked edits,
# composite it onto the original instead and print the verification report on stderr.
save() {
  local src="$1" dest="$2" diff_out="$3"
  if [[ "$lock" -eq 0 ]]; then
    cp "$src" "$dest"
    return
  fi
  local args=(composite --original "${inputs[0]}" --edited "$src" --out "$dest")
  local r
  for r in "${regions[@]+"${regions[@]}"}"; do args+=(--region "$r"); done
  [[ -n "$mask" ]] && args+=(--mask "$mask")
  [[ -n "$feather" ]] && args+=(--feather "$feather")
  [[ -n "$diff_out" ]] && args+=(--diff "$diff_out")
  echo "raw generated image: $src" >&2
  "${py[@]}" "$script_dir/edit_tools.py" "${args[@]}" >&2
}

if [[ ${#results[@]} -eq 1 ]]; then
  save "${results[0]}" "$out" "$diff"
  echo "$out"
else
  i=1
  for f in "${results[@]}"; do
    dest="$base-$i.$ext"
    diff_out=""
    [[ -n "$diff" ]] && diff_out="${diff%.*}-$i.png"
    save "$f" "$dest" "$diff_out"
    echo "$dest"
    i=$((i + 1))
  done
fi
