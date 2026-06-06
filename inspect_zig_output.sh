#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <file.zig>" >&2
  exit 2
fi

src="$1"
if [ ! -f "$src" ]; then
  echo "error: file not found: $src" >&2
  exit 2
fi

base="$(basename "$src" .zig)"
out_dir="/tmp/zig_pair_practice_${base}"
bin="$out_dir/$base"
asm="$out_dir/$base.s"
llvm_ir="$out_dir/$base.ll"
symbols="$out_dir/$base.nm.txt"
disasm="$out_dir/$base.disasm.txt"

mkdir -p "$out_dir"

zig build-exe "$src" \
  -O ReleaseFast \
  -femit-bin="$bin" \
  -femit-asm="$asm" \
  -femit-llvm-ir="$llvm_ir"

nm "$bin" > "$symbols" || true

if command -v objdump >/dev/null 2>&1; then
  objdump -d "$bin" > "$disasm" || true
elif command -v otool >/dev/null 2>&1; then
  otool -tvV "$bin" > "$disasm" || true
else
  echo "no objdump or otool found" > "$disasm"
fi

cat <<EOF
output: $out_dir
binary: $bin
assembly: $asm
llvm_ir: $llvm_ir
symbols: $symbols
disassembly: $disasm

try:
  rg "countThresholdBreached|thresholdFor|main|fcmp|br|load" "$llvm_ir"
  rg "countThresholdBreached|thresholdFor|main" "$asm" "$symbols" "$disasm"
EOF
