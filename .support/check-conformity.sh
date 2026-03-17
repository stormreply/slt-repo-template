#!/usr/bin/env bash
# check-conformity.sh — Verify a Terraform repo conforms to the SLT template.
# Run this script from the root of the repo you want to check.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$(pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

CHECKS=0
FAILURES=0
declare -a DIFFS=()   # pairs: template_file target_file rel_path (3 elements each)

checksum() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

pass()   { echo -e "  ${GREEN}[PASS]${NC}    $1";              CHECKS=$((CHECKS + 1)); }
fail()   { echo -e "  ${RED}[FAIL]${NC}    $1${2:+  ($2)}";   CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); }
extra()  { echo -e "  ${YELLOW}[EXTRA]${NC}   $1${2:+  ($2)}"; CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); }
copied() { echo -e "  ${YELLOW}[COPY]${NC}    $1  ($2)";       CHECKS=$((CHECKS + 1)); }
deleted(){ echo -e "  ${YELLOW}[DELETED]${NC} $1${2:+  ($2)}"; CHECKS=$((CHECKS + 1)); }

DIVIDER="────────────────────────────────────────────────────────"

echo ""
echo -e "${BOLD}SLT Template Conformity Check${NC}"
echo "$DIVIDER"
echo "  Template : $TEMPLATE_ROOT"
echo "  Target   : $TARGET_DIR"
echo "$DIVIDER"

# ── Collect template files ──────────────────────────────────────────────────

declare -a TEMPLATE_FILES=()
declare -a TEMPLATE_UNDERSCORE_NAMES=()

add_dir() {
    local dir="$1"
    if [[ -d "$TEMPLATE_ROOT/$dir" ]]; then
        while IFS= read -r -d '' f; do
            TEMPLATE_FILES+=("$dir/$(basename "$f")")
        done < <(find "$TEMPLATE_ROOT/$dir" -maxdepth 1 -type f -print0 | sort -z)
    fi
}

add_dir ".github/workflows"
add_dir ".support"

for f in "_sltconf.tf" "providers.tf" "terraform.tf"; do
    [[ -f "$TEMPLATE_ROOT/$f" ]] && TEMPLATE_FILES+=("$f")
done

# ── File integrity ──────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}File integrity${NC}"
echo ""

for rel in "${TEMPLATE_FILES[@]}"; do
    # Track root-level underscore filenames for the next section
    fname="$(basename "$rel")"
    [[ "$fname" == _* && "$rel" != */* ]] && TEMPLATE_UNDERSCORE_NAMES+=("$fname")

    template_file="$TEMPLATE_ROOT/$rel"
    target_file="$TARGET_DIR/$rel"

    if [[ ! -f "$target_file" ]]; then
        mkdir -p "$(dirname "$target_file")"
        cp "$template_file" "$target_file"
        copied "$rel" "copied from template"
        continue
    fi

    if [[ "$(checksum "$template_file")" == "$(checksum "$target_file")" ]]; then
        pass "$rel"
    elif [[ "$rel" == .github/* || "$rel" == .support/* || "$rel" == _sltconf.tf ]]; then
        cp "$template_file" "$target_file"
        copied "$rel" "overwritten from template"
    else
        fail "$rel" "checksum mismatch"
        DIFFS+=("$template_file" "$target_file" "$rel")
    fi
done

# ── Underscore file check ───────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Underscore file check (root level)${NC}"
echo ""

extra_found=false
while IFS= read -r -d '' f; do
    fname="$(basename "$f")"
    known=false
    for k in "${TEMPLATE_UNDERSCORE_NAMES[@]+"${TEMPLATE_UNDERSCORE_NAMES[@]}"}"; do
        [[ "$k" == "$fname" ]] && known=true && break
    done
    if ! $known; then
        if [[ "$fname" == *.tf ]]; then
            rm "$f"
            deleted "$fname" "not in template, removed"
        else
            extra "$fname" "not present in template"
        fi
        extra_found=true
    fi
done < <(find "$TARGET_DIR" -maxdepth 1 -type f -name '_*' -print0 2>/dev/null | sort -z)

if ! $extra_found; then
    pass "no extra underscore files at root level"
fi

# ── Diffs ───────────────────────────────────────────────────────────────────

if (( ${#DIFFS[@]} > 0 )); then
    echo ""
    echo -e "${BOLD}Diffs (template vs target)${NC}"

    i=0
    while (( i < ${#DIFFS[@]} )); do
        template_file="${DIFFS[$i]}"
        target_file="${DIFFS[$((i + 1))]}"
        rel="${DIFFS[$((i + 2))]}"
        i=$((i + 3))

        echo ""
        echo "$DIVIDER"
        echo -e "  ${RED}${BOLD}$rel${NC}"
        echo "$DIVIDER"
        diff --unified=3 \
            --label "template/$rel" \
            --label "target/$rel" \
            "$template_file" "$target_file" || true
    done
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "$DIVIDER"
if (( FAILURES == 0 )); then
    echo -e "  ${GREEN}${BOLD}All $CHECKS checks passed.${NC}"
else
    echo -e "  ${RED}${BOLD}$FAILURES of $CHECKS checks failed.${NC}"
fi
echo "$DIVIDER"
echo ""

if (( FAILURES > 0 )); then
    exit 1
fi
