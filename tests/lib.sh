#!/usr/bin/env bash
# 極簡測試輔助（無外部相依）。每個 test_*.sh source 本檔，結尾呼叫 finish。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

_PASS=0; _FAIL=0; _SKIP=0
if [[ -t 1 ]]; then C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'; else C_G=; C_R=; C_Y=; C_0=; fi

ok()   { _PASS=$((_PASS+1)); echo "  ${C_G}✓${C_0} $1"; }
ko()   { _FAIL=$((_FAIL+1)); echo "  ${C_R}✗${C_0} $1"; [[ -n "${2:-}" ]] && echo "      └─ $2"; }
skip() { _SKIP=$((_SKIP+1)); echo "  ${C_Y}∼${C_0} $1 (skipped: ${2:-})"; }

# assert_eq <name> <expected> <actual>
assert_eq() { [[ "$2" == "$3" ]] && ok "$1" || ko "$1" "expected=[$2] actual=[$3]"; }
# assert_contains <name> <haystack> <needle>
assert_contains() { [[ "$2" == *"$3"* ]] && ok "$1" || ko "$1" "[$3] not found in output"; }
# assert_not_contains <name> <haystack> <needle>
assert_not_contains() { [[ "$2" != *"$3"* ]] && ok "$1" || ko "$1" "[$3] unexpectedly present"; }
# assert_cmd <name> <cmd...>  — passes if command exits 0
assert_cmd() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else ko "$n" "cmd failed: $*"; fi; }
# assert_fail <name> <cmd...> — passes if command exits non-zero
assert_fail() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ko "$n" "cmd unexpectedly succeeded: $*"; else ok "$n"; fi; }

section() { echo ""; echo "▸ $1"; }

finish() {
  echo ""
  echo "  結果：${C_G}${_PASS} passed${C_0}, ${C_R}${_FAIL} failed${C_0}, ${C_Y}${_SKIP} skipped${C_0}"
  [[ $_FAIL -eq 0 ]]
}
