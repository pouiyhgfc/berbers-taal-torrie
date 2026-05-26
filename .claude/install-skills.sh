#!/usr/bin/env bash
# ============================================================
# Claude Skills Installer
# Installeert skills van:
#   - https://github.com/Jeffallan/claude-skills  (66 skills)
#   - https://github.com/alirezarezvani/claude-skills (700+ skills)
# ============================================================
set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[skills-installer] Checking installed skills..."

JEFFALLAN_MARKER="${SKILLS_DIR}/.jeffallan-installed"
ALIREZA_MARKER="${SKILLS_DIR}/.alireza-installed"

mkdir -p "$SKILLS_DIR"

# --- Jeffallan (66 skills) ---
if [ ! -f "$JEFFALLAN_MARKER" ]; then
    echo "[skills-installer] Downloading Jeffallan/claude-skills (66 skills)..."
    git clone --depth=1 https://github.com/Jeffallan/claude-skills.git \
        "${TMP_DIR}/jeffallan" 2>/dev/null

    count=0
    for skill_dir in "${TMP_DIR}/jeffallan/skills"/*/; do
        skill_name=$(basename "$skill_dir")
        if [ ! -d "${SKILLS_DIR}/${skill_name}" ]; then
            cp -r "$skill_dir" "${SKILLS_DIR}/${skill_name}"
            ((count++)) || true
        fi
    done
    touch "$JEFFALLAN_MARKER"
    echo "[skills-installer] ✓ Jeffallan: ${count} skills installed"
else
    echo "[skills-installer] ✓ Jeffallan skills already installed (verwijder ${JEFFALLAN_MARKER} om opnieuw te installeren)"
fi

# --- Alireza (700+ skills) ---
if [ ! -f "$ALIREZA_MARKER" ]; then
    echo "[skills-installer] Downloading alirezarezvani/claude-skills (700+ skills)..."
    git clone --depth=1 https://github.com/alirezarezvani/claude-skills.git \
        "${TMP_DIR}/alireza" 2>/dev/null

    count=0
    while IFS= read -r -d '' skill_file; do
        skill_dir=$(dirname "$skill_file")
        skill_name=$(basename "$skill_dir")
        dest="${SKILLS_DIR}/${skill_name}"
        if [ ! -d "$dest" ]; then
            cp -r "$skill_dir" "$dest"
        else
            cp -r "$skill_dir" "${dest}-alireza"
        fi
        ((count++)) || true
    done < <(find "${TMP_DIR}/alireza" -name "SKILL.md" -print0)

    touch "$ALIREZA_MARKER"
    echo "[skills-installer] ✓ Alireza: ${count} skills installed"
else
    echo "[skills-installer] ✓ Alireza skills already installed (verwijder ${ALIREZA_MARKER} om opnieuw te installeren)"
fi

total=$(ls "$SKILLS_DIR" | grep -v '^\.' | wc -l)
echo "[skills-installer] 🎉 Totaal ${total} skills beschikbaar in ~/.claude/skills/"
