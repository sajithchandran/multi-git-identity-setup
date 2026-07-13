#!/usr/bin/env bash
# =============================================================================
# Add a New GitHub Identity
# =============================================================================
# Run this script to add another profile to an already-configured setup.
# It generates an SSH key, updates SSH config, creates the gitconfig include,
# and registers the includeIf in ~/.gitconfig — without disturbing existing
# profiles.
#
# Usage:
#   chmod +x add-identity.sh
#   ./add-identity.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Add Another GitHub Identity                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Detect existing profiles
    local existing=()
    if [[ -f "$HOME/.ssh/config" ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^Host[[:space:]]+github\.com-(.+) ]]; then
                existing+=("${BASH_REMATCH[1]}")
            fi
        done < "$HOME/.ssh/config"
    fi

    if [[ ${#existing[@]} -gt 0 ]]; then
        info "Existing profiles: ${existing[*]}"
    else
        warn "No existing profiles found. Run setup.sh first!"
    fi
    echo ""

    # ── Collect ─────────────────────────────────────────────────────────────
    read -r -p "New profile name (e.g., client, freelance): " profile
    profile="${profile,,}"
    profile="${profile// /-}"

    if [[ -z "$profile" ]]; then
        error "Profile name cannot be empty."
        exit 1
    fi

    # Check for duplicate
    for p in "${existing[@]}"; do
        if [[ "$p" == "$profile" ]]; then
            error "Profile '${profile}' already exists!"
            exit 1
        fi
    done

    read -r -p "Git user name for '${profile}': " name
    read -r -p "Git email for '${profile}': " email

    if [[ -z "$name" || -z "$email" ]]; then
        error "Name and email cannot be empty."
        exit 1
    fi

    # ── SSH key ─────────────────────────────────────────────────────────────
    local key_path="$HOME/.ssh/id_${profile}"
    if [[ ! -f "$key_path" ]]; then
        info "Generating SSH key..."
        ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
        ok "Key generated: ${key_path}"
        echo ""
        info "Add this public key to GitHub:"
        cat "${key_path}.pub"
        echo ""
    else
        warn "SSH key ${key_path} already exists — reusing."
    fi

    # ── SSH config ──────────────────────────────────────────────────────────
    local host_alias="github.com-${profile}"
    if ! grep -q "Host ${host_alias}" "$HOME/.ssh/config" 2>/dev/null; then
        info "Adding SSH config entry..."
        cat >> "$HOME/.ssh/config" <<EOF

# ── ${profile} identity ───────────────────────────────────────────────────
Host ${host_alias}
  HostName github.com
  User git
  IdentityFile ${key_path}
EOF
        ok "SSH config entry added."
    else
        warn "SSH config entry for '${host_alias}' already exists."
    fi

    # ── Gitconfig include ───────────────────────────────────────────────────
    local include_file="$HOME/.gitconfig-${profile}"
    if [[ ! -f "$include_file" ]]; then
        info "Creating gitconfig include..."
        cat > "$include_file" <<EOF
# ~/.gitconfig-${profile}
# Auto-included for repos whose remote URL host is \`github.com-${profile}\`.

[user]
    name = ${name}
    email = ${email}
EOF
        ok "Gitconfig include created: ${include_file}"
    else
        warn "Gitconfig include ${include_file} already exists."
    fi

    # ── Global .gitconfig ───────────────────────────────────────────────────
    if ! grep -q "github.com-${profile}" "$HOME/.gitconfig" 2>/dev/null; then
        info "Adding includeIf to ~/.gitconfig..."
        cat >> "$HOME/.gitconfig" <<EOF

# ── ${profile} identity override ──────────────────────────────────────────
[includeIf "hasconfig:remote.*.url:git@github.com-${profile}:*/**"]
    path = ~/.gitconfig-${profile}
EOF
        ok "includeIf added."
    else
        warn "includeIf for '${profile}' already exists in ~/.gitconfig."
    fi

    # ── Done ────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Profile '${profile}' added successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Clone a repo with:"
    echo "  git clone git@github.com-${profile}:org/repo.git"
    echo ""
    echo "Or update an existing repo:"
    echo "  git remote set-url origin git@github.com-${profile}:org/repo.git"
}

main
