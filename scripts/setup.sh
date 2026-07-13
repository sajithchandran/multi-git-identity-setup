#!/usr/bin/env bash
# =============================================================================
# Multi-GitHub Identity Setup Script
# =============================================================================
# This script automates the setup of multiple GitHub identities on a single
# machine. It generates SSH keys, configures SSH, and sets up Git's
# conditional includes so that the correct name/email is used per repository.
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# You will be prompted to provide:
#   - A profile name (e.g., "personal", "work", "opensource")
#   - Your Git user name for that profile
#   - Your Git email for that profile
#   =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prerequisites() {
    if ! command -v git &>/dev/null; then
        error "Git is not installed. Please install git first."
        exit 1
    fi

    if ! command -v ssh-keygen &>/dev/null; then
        error "ssh-keygen not found. Please install OpenSSH."
        exit 1
    fi

    if command -v gh &>/dev/null; then
        info "GitHub CLI (gh) detected — you can use 'gh auth login' for token-based auth."
    else
        warn "GitHub CLI (gh) not found. Install it from https://cli.github.com/ for easier auth."
    fi

    # Ensure ~/.ssh exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    ok "All prerequisites satisfied."
}

# ── Detect existing profiles ──────────────────────────────────────────────────
detect_existing_profiles() {
    local profiles=()
    if [[ -f "$HOME/.ssh/config" ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^Host[[:space:]]+github\.com-(.+) ]]; then
                profiles+=("${BASH_REMATCH[1]}")
            fi
        done < "$HOME/.ssh/config"
    fi
    echo "${profiles[@]}"
}

# ── Generate SSH key ──────────────────────────────────────────────────────────
generate_ssh_key() {
    local profile="$1"
    local email="$2"
    local key_path="$HOME/.ssh/id_${profile}"

    if [[ -f "$key_path" ]]; then
        warn "SSH key already exists at $key_path — skipping generation."
        return
    fi

    info "Generating ED25519 SSH key for profile '$profile'..."
    ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
    ok "SSH key generated: $key_path"

    echo ""
    info "Add this public key to GitHub (https://github.com/settings/keys):"
    cat "${key_path}.pub"
    echo ""
}

# ── Update SSH config ─────────────────────────────────────────────────────────
update_ssh_config() {
    local profile="$1"
    local host_alias="github.com-${profile}"
    local key_path="$HOME/.ssh/id_${profile}"

    if grep -q "Host ${host_alias}" "$HOME/.ssh/config" 2>/dev/null; then
        warn "SSH config entry for '${host_alias}' already exists — skipping."
        return
    fi

    info "Adding SSH config entry for '${host_alias}'..."

    cat >> "$HOME/.ssh/config" <<EOF

# ── ${profile} identity ───────────────────────────────────────────────────
Host ${host_alias}
  HostName github.com
  User git
  IdentityFile ${key_path}
EOF

    ok "SSH config updated."
}

# ── Create gitconfig include ──────────────────────────────────────────────────
create_gitconfig_include() {
    local profile="$1"
    local name="$2"
    local email="$3"
    local include_file="$HOME/.gitconfig-${profile}"

    if [[ -f "$include_file" ]]; then
        warn "Git config include already exists at ${include_file} — skipping."
        return
    fi

    info "Creating gitconfig include at ${include_file}..."

    cat > "$include_file" <<EOF
# ~/.gitconfig-${profile}
# Auto-included for repos whose remote URL host is \`github.com-${profile}\`.
# Sourced via [includeIf] in ~/.gitconfig when the remote URL matches
# git@github.com-${profile}:*/**

[user]
    name = ${name}
    email = ${email}
EOF

    ok "Gitconfig include created."
}

# ── Update global .gitconfig ──────────────────────────────────────────────────
update_global_gitconfig() {
    local profile="$1"
    local include_file="~/.gitconfig-${profile}"
    local include_line="[includeIf \"hasconfig:remote.*.url:git@github.com-${profile}:*/**\"]"
    local path_line="    path = ${include_file}"

    if grep -q "github.com-${profile}" "$HOME/.gitconfig" 2>/dev/null; then
        warn "includeIf for '${profile}' already exists in ~/.gitconfig — skipping."
        # Still ensure the includeIf is before the [user] block (it should be at the bottom)
        return
    fi

    info "Adding includeIf for '${profile}' to ~/.gitconfig..."

    # Ensure ~/.gitconfig exists
    if [[ ! -f "$HOME/.gitconfig" ]]; then
        cat > "$HOME/.gitconfig" <<'EOF'
[user]
    name = Your Name
    email = your.email@default.com
EOF
    fi

    # Append includeIf BEFORE any trailing comments or empty lines at the end.
    # The includeIf MUST appear AFTER the [user] block so it overrides the fall-through.
    cat >> "$HOME/.gitconfig" <<EOF

# ── ${profile} identity override ──────────────────────────────────────────
${include_line}
${path_line}
EOF

    ok "includeIf added to ~/.gitconfig."
}

# ── Print next steps ──────────────────────────────────────────────────────────
print_next_steps() {
    local profile="$1"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Profile '${profile}' configured successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Add the public key to GitHub:"
    echo "     https://github.com/settings/keys"
    echo ""
    echo "  2. For NEW repos — clone using the profile alias:"
    echo "     git clone git@github.com-${profile}:org/repo.git"
    echo ""
    echo "  3. For EXISTING repos — update the remote:"
    echo "     cd /path/to/repo"
    echo "     git remote set-url origin git@github.com-${profile}:org/repo.git"
    echo ""
    echo "  4. Verify the identity is applied:"
    echo "     cd /path/to/repo"
    echo "     git config user.name   # Should show '${name}'"
    echo "     git config user.email  # Should show '${email}'"
    echo ""
    echo "  5. (Optional) Log in with GitHub CLI for this account:"
    echo "     gh auth login -h github.com"
    echo "     # Then select the account when prompted"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Multi-GitHub Identity Setup                    ║${NC}"
    echo -e "${BLUE}║    Configure one profile at a time               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run the script interactively, one profile at a time
    local existing_profiles
    existing_profiles=$(detect_existing_profiles)

    if [[ -n "$existing_profiles" ]]; then
        info "Existing profiles detected: ${existing_profiles}"
        echo ""
    fi

    echo "We'll walk you through adding ONE profile now."
    echo "Run this script again to add additional profiles."
    echo ""

    # ── Collect profile info ────────────────────────────────────────────────
    read -r -p "Profile name (e.g., personal, work, opensource): " profile
    profile="${profile,,}" # lowercase
    profile="${profile// /-}" # spaces to hyphens

    if [[ -z "$profile" ]]; then
        error "Profile name cannot be empty."
        exit 1
    fi

    read -r -p "Git user name for '${profile}': " name
    if [[ -z "$name" ]]; then
        error "User name cannot be empty."
        exit 1
    fi

    read -r -p "Git email for '${profile}': " email
    if [[ -z "$email" ]]; then
        error "Email cannot be empty."
        exit 1
    fi

    echo ""

    # ── Execute each step ───────────────────────────────────────────────────
    check_prerequisites
    generate_ssh_key "$profile" "$email"
    update_ssh_config "$profile"
    create_gitconfig_include "$profile" "$name" "$email"
    update_global_gitconfig "$profile"

    # ── Done ────────────────────────────────────────────────────────────────
    print_next_steps "$profile"
}

main
