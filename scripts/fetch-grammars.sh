#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES="$PROJECT_ROOT/Sources"
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

ALL_LANGS="kotlin typescript go zig rust cpp python java"

fetch_language() {
  local lang="$1"
  local repo tag func_name target guard src_subdir

  case "$lang" in
    kotlin)
      repo="https://github.com/fwcd/tree-sitter-kotlin"
      tag="0.3.8"
      func_name="tree_sitter_kotlin"
      target="TreeSitterKotlinGrammar"
      guard="TREE_SITTER_KOTLIN_GRAMMAR_H"
      src_subdir="src"
      ;;
    typescript)
      repo="https://github.com/tree-sitter/tree-sitter-typescript"
      tag="v0.23.2"
      func_name="tree_sitter_tsx"
      target="TreeSitterTypeScriptGrammar"
      guard="TREE_SITTER_TYPESCRIPT_GRAMMAR_H"
      src_subdir="tsx/src"
      ;;
    go)
      repo="https://github.com/tree-sitter/tree-sitter-go"
      tag="v0.23.4"
      func_name="tree_sitter_go"
      target="TreeSitterGoGrammar"
      guard="TREE_SITTER_GO_GRAMMAR_H"
      src_subdir="src"
      ;;
    zig)
      repo="https://github.com/tree-sitter-grammars/tree-sitter-zig"
      tag="v1.1.2"
      func_name="tree_sitter_zig"
      target="TreeSitterZigGrammar"
      guard="TREE_SITTER_ZIG_GRAMMAR_H"
      src_subdir="src"
      ;;
    rust)
      repo="https://github.com/tree-sitter/tree-sitter-rust"
      tag="v0.24.0"
      func_name="tree_sitter_rust"
      target="TreeSitterRustGrammar"
      guard="TREE_SITTER_RUST_GRAMMAR_H"
      src_subdir="src"
      ;;
    cpp)
      repo="https://github.com/tree-sitter/tree-sitter-cpp"
      tag="v0.23.4"
      func_name="tree_sitter_cpp"
      target="TreeSitterCppGrammar"
      guard="TREE_SITTER_CPP_GRAMMAR_H"
      src_subdir="src"
      ;;
    python)
      repo="https://github.com/tree-sitter/tree-sitter-python"
      tag="v0.23.6"
      func_name="tree_sitter_python"
      target="TreeSitterPythonGrammar"
      guard="TREE_SITTER_PYTHON_GRAMMAR_H"
      src_subdir="src"
      ;;
    java)
      repo="https://github.com/tree-sitter/tree-sitter-java"
      tag="v0.23.5"
      func_name="tree_sitter_java"
      target="TreeSitterJavaGrammar"
      guard="TREE_SITTER_JAVA_GRAMMAR_H"
      src_subdir="src"
      ;;
    *)
      echo "Unknown language: $lang"
      echo "Available: $ALL_LANGS"
      exit 1
      ;;
  esac

  echo "==> Fetching $lang ($repo@$tag)..."

  local clone_dir="$TMPDIR_BASE/$lang"
  git clone --depth 1 --branch "$tag" "$repo" "$clone_dir" 2>/dev/null

  local src_dir="$clone_dir/$src_subdir"
  local dest="$SOURCES/$target"

  mkdir -p "$dest/include" "$dest/tree_sitter"

  # Copy parser.c
  cp "$src_dir/parser.c" "$dest/parser.c"

  # Copy scanner if exists (.c or .cc)
  if [ -f "$src_dir/scanner.c" ]; then
    cp "$src_dir/scanner.c" "$dest/scanner.c"
  elif [ -f "$src_dir/scanner.cc" ]; then
    cp "$src_dir/scanner.cc" "$dest/scanner.cc"
  fi

  # Copy all tree_sitter headers
  if [ -d "$src_dir/tree_sitter" ]; then
    cp "$src_dir/tree_sitter/"*.h "$dest/tree_sitter/" 2>/dev/null || true
  fi

  # TypeScript: copy common scanner.h and fix include path
  if [ "$lang" = "typescript" ] && [ -f "$clone_dir/common/scanner.h" ]; then
    cp "$clone_dir/common/scanner.h" "$dest/scanner.h"
    sed -i '' 's|#include "../../common/scanner.h"|#include "scanner.h"|g' "$dest/scanner.c" 2>/dev/null || true
  fi

  # Generate public header
  cat > "$dest/include/${target}.h" <<HEADER
#ifndef ${guard}
#define ${guard}

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TSLanguage TSLanguage;
const TSLanguage *${func_name}(void);

#ifdef __cplusplus
}
#endif

#endif
HEADER

  echo "    -> $dest"
}

# Main
if [ $# -eq 0 ]; then
  echo "Usage: $0 <language|all>"
  echo "Languages: $ALL_LANGS"
  exit 1
fi

if [ "$1" = "all" ]; then
  for lang in $ALL_LANGS; do
    fetch_language "$lang"
  done
else
  for lang in "$@"; do
    fetch_language "$lang"
  done
fi

echo "Done."
