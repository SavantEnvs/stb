#!/usr/bin/env bash
# Builds the fuzz harnesses (sanitized, DWARF 3) + standalone reproducers, and the functional
# check binaries (normal flags) that mayhem/test.sh runs. stb is header-only, so the "project"
# is compiled into each harness translation unit and carries the sanitizer/coverage flags.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Leak detection off at build time; ASan/UBSan stay active.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$WORK/lsan_off.o"
# The standalone driver is C; compile it separately so the C++ harness links against C symbols.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$WORK/standalone_main.o"

# 1) libFuzzer targets + standalone reproducers
# stb_png_read_fuzzer / stbi_read_fuzzer: the two harnesses OSS-Fuzz builds from tests/ossfuzz.sh
# (same source, PNG-only vs. all-formats via STBI_ONLY_PNG).
build_c() { # <name> <extra cflags...>
  local name="$1"; shift
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$@" -I. tests/stbi_read_fuzzer.c "$WORK/lsan_off.o" \
      $LIB_FUZZING_ENGINE -lm -o "$SRC/$name"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$@" -I. tests/stbi_read_fuzzer.c "$WORK/standalone_main.o" \
      "$WORK/lsan_off.o" -lm -o "$SRC/$name-standalone"
}
build_c stb_png_read_fuzzer -DSTBI_ONLY_PNG
build_c stbi_read_fuzzer

# stb_c_lexer_fuzzer: in-tree tests/stb_c_lexer_fuzzer.cpp, minus the SELF_TEST main().
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I. mayhem/harnesses/stb_c_lexer_fuzzer.cpp \
    "$WORK/lsan_off.o" $LIB_FUZZING_ENGINE -o "$SRC/stb_c_lexer_fuzzer"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I. mayhem/harnesses/stb_c_lexer_fuzzer.cpp \
    "$WORK/standalone_main.o" "$WORK/lsan_off.o" -o "$SRC/stb_c_lexer_fuzzer-standalone"

# 2) Functional check binaries, NORMAL flags (no sanitizers), run by mayhem/test.sh from tests/.
$CC -O1 $COVERAGE_FLAGS -I. mayhem/png_regress_check.c -lm -o "$SRC/stb_png_regress_check"
# C++ variant: the C one (tests/test_ds.c) does not compile under clang >= 16 (int-conversion on struct-key hmgets)
$CXX -O1 -w -std=c++11 $COVERAGE_FLAGS -DDS_TEST -I. tests/test_ds_cpp.cpp -lm -o "$SRC/stb_ds_unit_tests"
