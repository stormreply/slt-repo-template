#!/usr/bin/env bash
# check-files.sh — Verify a Terraform repo conforms to the SLT template.
# Run this script from the root of the repo you want to check.
#
# Options:
#   --quiet,      -q   Suppress verbose terminal output (colors/sections)
#   --list-files, -l   Print all collected template files before checking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$(pwd)"

# ── Flags ───────────────────────────────────────────────────────────────────

VERBOSE=true
LIST_FILES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q)      VERBOSE=false; shift ;;
        --list-files|-l) LIST_FILES=true;  shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── State ────────────────────────────────────────────────────────────────────

CHECKS=0
declare -a DIFFS=()

declare -a ALLOW_DIFF=(
    "providers.tf"
    "terraform.tf"
)

declare -a DELETE_FILES=(
    "_metadata.tf"
    "_default_tags.tf"
)

declare -a UNWANTED_PATTERNS=(
    "local._name_tag"
)

declare -a MD_COPIED=()
declare -a MD_OVERWRITTEN=()
declare -a MD_PATTERNS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

checksum() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

vecho() { $VERBOSE && echo -e "$@" || true; }

pass()    { vecho "  ${GREEN}[PASS]${NC}    $1";              CHECKS=$((CHECKS + 1)); }
fail()    { vecho "  ${RED}[FAIL]${NC}    $1${2:+  ($2)}";    CHECKS=$((CHECKS + 1)); }
hint()    { vecho "  ${CYAN}[HINT]${NC}    $1${2:+  ($2)}";   CHECKS=$((CHECKS + 1)); }
deleted() { vecho "  ${YELLOW}[DELETED]${NC} $1${2:+  ($2)}"; CHECKS=$((CHECKS + 1)); }
copied()  { vecho "  ${YELLOW}[COPY]${NC}    $1  ($2)";       CHECKS=$((CHECKS + 1)); MD_COPIED+=("$1"); }
synced()  { vecho "  ${YELLOW}[SYNC]${NC}    $1  ($2)";       CHECKS=$((CHECKS + 1)); MD_OVERWRITTEN+=("$1"); }

DIVIDER="────────────────────────────────────────────────────────"

if $VERBOSE; then
    echo ""
    echo -e "${BOLD}SLT Template Conformity Check${NC}"
    echo "$DIVIDER"
    echo "  Template : $TEMPLATE_ROOT"
    echo "  Target   : $TARGET_DIR"
    echo "$DIVIDER"
fi

# ── Collect template files ──────────────────────────────────────────────────

declare -a TEMPLATE_FILES=()
declare -a TEMPLATE_SOURCES=()  # parallel to TEMPLATE_FILES: "dir:NAME" or "file"

add_dir() {
    local dir="$1"
    if [[ -d "$TEMPLATE_ROOT/$dir" ]]; then
        while IFS= read -r -d '' f; do
            TEMPLATE_FILES+=("$dir/$(basename "$f")")
            TEMPLATE_SOURCES+=("dir:$dir")
        done < <(find "$TEMPLATE_ROOT/$dir" -maxdepth 1 -type f -print0 | sort -z)
    fi
}

add_file() {
    local f="$1"
    if [[ -f "$TEMPLATE_ROOT/$f" ]]; then
        TEMPLATE_FILES+=("$f")
        TEMPLATE_SOURCES+=("file")
    fi
}

add_dir ".github/workflows"
add_dir ".support"
add_file "_sltconf.tf"
add_file "providers.tf"
add_file "terraform.tf"

# ── List files ───────────────────────────────────────────────────────────────

if $LIST_FILES; then
    echo ""
    echo "Template files:"
    for i in "${!TEMPLATE_FILES[@]}"; do
        printf "  [%-20s] %s\n" "${TEMPLATE_SOURCES[$i]}" "${TEMPLATE_FILES[$i]}"
    done
    echo ""
fi

# ── File integrity ──────────────────────────────────────────────────────────

vecho ""
vecho "${BOLD}File integrity${NC}"
vecho ""

for rel in "${TEMPLATE_FILES[@]}"; do
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
    elif [[ " ${ALLOW_DIFF[*]} " == *" $rel "* ]]; then
        hint "$rel" "differs from template (allowed)"
        DIFFS+=("$template_file" "$target_file" "$rel")
    else
        cp "$template_file" "$target_file"
        synced "$rel" "overwritten from template"
    fi
done

# ── File cleanup ───────────────────────────────────────────────────────────

vecho ""
vecho "${BOLD}File cleanup${NC}"
vecho ""

cleanup_found=false
for fname in "${DELETE_FILES[@]}"; do
    target_file="$TARGET_DIR/$fname"
    if [[ -f "$target_file" ]]; then
        rm "$target_file"
        deleted "$fname" "listed for removal, deleted"
        cleanup_found=true
    fi
done

if ! $cleanup_found; then
    pass "no files to clean up"
fi

# ── Pattern check ──────────────────────────────────────────────────────────

vecho ""
vecho "${BOLD}Pattern check (.tf files)${NC}"
vecho ""

pattern_issues=false
while IFS= read -r -d '' f; do
    rel="${f#"$TARGET_DIR"/}"
    [[ "$(basename "$f")" == "_sltconf.tf" ]] && continue
    for pattern in "${UNWANTED_PATTERNS[@]}"; do
        if grep -qF "$pattern" "$f"; then
            fail "$rel" "contains unwanted pattern: $pattern"
            MD_PATTERNS+=("\`$rel\`: contains \`$pattern\`")
            pattern_issues=true
        fi
    done
done < <(find "$TARGET_DIR" -type f -name '*.tf' \
    -not -path '*/.terraform/*' -print0 2>/dev/null | sort -z)

if ! $pattern_issues; then
    pass "no unwanted patterns found"
fi

# ── Diffs ───────────────────────────────────────────────────────────────────

if $VERBOSE && (( ${#DIFFS[@]} > 0 )); then
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
        echo -e "  ${CYAN}${BOLD}$rel${NC}"
        echo "$DIVIDER"
        diff --unified=3 \
            --label "template/$rel" \
            --label "target/$rel" \
            "$template_file" "$target_file" || true
    done
fi

# ── Verbose terminal summary ─────────────────────────────────────────────────

FAILURES=$(( ${#MD_COPIED[@]} + ${#MD_OVERWRITTEN[@]} + ${#MD_PATTERNS[@]} ))

if $VERBOSE; then
    echo ""
    echo "$DIVIDER"
    if (( FAILURES == 0 )); then
        echo -e "  ${GREEN}${BOLD}All $CHECKS checks passed.${NC}"
    else
        echo -e "  ${RED}${BOLD}$FAILURES of $CHECKS checks failed.${NC}"
    fi
    echo "$DIVIDER"
    echo ""
fi

# ── Markdown summary ─────────────────────────────────────────────────────────

md_summary() {
    if (( ${#MD_COPIED[@]} > 0 )); then
        echo "Files missing"
        echo ""
        for f in "${MD_COPIED[@]}"; do echo "- \`$f\`"; done
        echo ""
    fi
    if (( ${#MD_OVERWRITTEN[@]} > 0 )); then
        echo "Files not in sync"
        echo ""
        for f in "${MD_OVERWRITTEN[@]}"; do echo "- \`$f\`"; done
        echo ""
    fi
    if (( ${#MD_PATTERNS[@]} > 0 )); then
        echo "Files with unwanted patterns"
        echo ""
        for entry in "${MD_PATTERNS[@]}"; do echo "- $entry"; done
    fi
}


write_step_summary() {
    report=$1
    if [ -n "$report" ] ; then
        cat << EOF
> [!CAUTION]
> Issues have been found during file check. See below:

$report
EOF
    else
        echo "No compliance issues found."
    fi
}


if (( FAILURES > 0 )); then

    report=$(md_summary)
    # echo "$report"
    [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] \
    && write_step_summary "$report" >> $GITHUB_STEP_SUMMARY

    exit 1
fi
