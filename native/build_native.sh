#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_file="$script_dir/kudog_native.c"
output_path=${1:-"$repo_root/assets/libkudog_native.dylib"}

mkdir -p "$(dirname -- "$output_path")"

if command -v clang >/dev/null 2>&1; then
  compiler=clang
elif command -v gcc >/dev/null 2>&1; then
  compiler=gcc
else
  echo "Neither clang nor gcc was found in PATH." >&2
  exit 1
fi

"$compiler" -dynamiclib -O3 -std=c11 -o "$output_path" "$source_file"
echo "Built native macOS library: $output_path"
