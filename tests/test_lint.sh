#!/usr/bin/env bash
# 業界主流靜態/安全掃描：shellcheck（shell）、hadolint（Dockerfile）、gitleaks（機密）。
# 工具未安裝則略過（brew install shellcheck hadolint gitleaks）。容器漏洞掃描(trivy)較重，見 make lint-trivy。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

echo "═══ Lint / 安全掃描 (test_lint) ═══"

section "shellcheck（所有 .sh）"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r f; do
    if shellcheck -S warning -e SC1090,SC1091 "$f" >/tmp/sc.out 2>&1; then ok "shellcheck $f"; else ko "shellcheck $f" "$(head -8 /tmp/sc.out)"; fi
  done < <(find deploy scripts tests -name '*.sh' 2>/dev/null | sort)
else
  skip "shellcheck" "未安裝（brew install shellcheck）"
fi

section "hadolint（Dockerfile）"
if command -v hadolint >/dev/null 2>&1; then
  # DL3008(未釘 apt 版本) 對部署映像可接受 → 忽略
  if hadolint --ignore DL3008 --ignore DL3059 deploy/Dockerfile >/tmp/hl.out 2>&1; then ok "hadolint Dockerfile"; else ko "hadolint Dockerfile" "$(head -12 /tmp/hl.out)"; fi
else
  skip "hadolint" "未安裝（brew install hadolint）"
fi

section "gitleaks（機密掃描，git 已追蹤內容）"
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --redact -r /tmp/gl.json >/tmp/gl.out 2>&1; then ok "gitleaks：無洩漏的機密"; else ko "gitleaks 偵測到機密" "$(grep -iE 'secret|finding|rule' /tmp/gl.out | head -6)"; fi
else
  skip "gitleaks" "未安裝（brew install gitleaks）"
fi

finish
