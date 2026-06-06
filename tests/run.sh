#!/usr/bin/env bash
# 測試總指揮：依序跑 static → config → integration，彙總結果。
# 用法：
#   bash tests/run.sh            # static + config + integration
#   bash tests/run.sh --no-docker  # 跳過整合測試
#   bash tests/run.sh --live     # 額外跑線上煙霧測試
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

suites=(test_static.sh test_docs.sh test_config.sh test_makefile.sh)
[[ "$*" == *--no-docker* ]] || suites+=(test_integration.sh)
[[ "$*" == *--live* ]] && suites+=(test_live.sh)

declare -a results
rc=0
for s in "${suites[@]}"; do
  echo ""; echo "════════════════════════════════════════════"
  if bash "$DIR/$s"; then results+=("✓ $s"); else results+=("✗ $s"); rc=1; fi
done

echo ""; echo "════════════════════════════════════════════"
echo "總覽："
for r in "${results[@]}"; do echo "  $r"; done
echo "════════════════════════════════════════════"
[[ $rc -eq 0 ]] && echo "全部通過 ✅" || echo "有測試失敗 ❌"
exit $rc
