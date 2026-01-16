#!/usr/bin/env bash
# claude-jail remote installer
# Usage:
#   curl -sSL https://raw.githubusercontent.com/mbarlow12/claude-jail/main/install-remote.sh | bash
#   VERSION=v0.1.0 curl -sSL ... | bash  # Pin to specific version
#
# Environment variables:
#   VERSION     - Specific version to install (e.g., v0.1.0). Default: latest
#   INSTALL_DIR - Installation directory. Default: $ZSH_CUSTOM/plugins/claude-jail

set -euo pipefail

REPO="mbarlow12/claude-jail"
INSTALL_DIR="${INSTALL_DIR:-${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/plugins/claude-jail}"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

die() {
    error "$@"
    exit 1
}

check_dependencies() {
    local missing=()

    command -v curl &>/dev/null || command -v wget &>/dev/null || missing+=("curl or wget")
    command -v tar &>/dev/null || missing+=("tar")
    command -v bwrap &>/dev/null || missing+=("bubblewrap")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install bubblewrap:"
        echo "  Debian/Ubuntu: sudo apt install bubblewrap"
        echo "  Arch:          sudo pacman -S bubblewrap"
        echo "  Fedora:        sudo dnf install bubblewrap"
        exit 1
    fi
}

get_latest_version() {
    local url="https://api.github.com/repos/${REPO}/releases/latest"

    if command -v curl &>/dev/null; then
        curl -sSL "$url" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/'
    else
        wget -qO- "$url" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/'
    fi
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl &>/dev/null; then
        curl -sSL "$url" -o "$output"
    else
        wget -q "$url" -O "$output"
    fi
}

main() {
    echo ""
    echo "  claude-jail installer"
    echo "  ====================="
    echo ""

    check_dependencies

    # Determine version
    local version="${VERSION:-}"
    if [[ -z "$version" ]]; then
        info "Fetching latest version..."
        version=$(get_latest_version)
        if [[ -z "$version" ]]; then
            # No releases yet - fall back to git clone
            warn "No releases found. Installing from main branch..."
            install_from_git
            return
        fi
    fi

    info "Version: $version"
    info "Install directory: $INSTALL_DIR"
    echo ""

    # Check for existing installation
    if [[ -d "$INSTALL_DIR" ]]; then
        local existing_version=""
        if [[ -f "$INSTALL_DIR/VERSION" ]]; then
            existing_version=$(cat "$INSTALL_DIR/VERSION")
        fi

        if [[ -n "$existing_version" ]]; then
            if [[ "v$existing_version" == "$version" ]]; then
                success "Already installed: v$existing_version"
                exit 0
            fi
            warn "Existing installation found: v$existing_version"
            info "Upgrading to $version..."
        else
            warn "Existing installation found (unknown version)"
            info "Upgrading to $version..."
        fi

        # Backup existing installation
        local backup_dir="${INSTALL_DIR}.backup.$(date +%s)"
        mv "$INSTALL_DIR" "$backup_dir"
        info "Backed up existing installation to $backup_dir"
    fi

    # Download and extract
    local version_num="${version#v}"
    local tarball_url="https://github.com/${REPO}/releases/download/${version}/claude-jail-${version_num}.tar.gz"
    local tmpdir=$(mktemp -d)
    local tarball="$tmpdir/claude-jail.tar.gz"

    info "Downloading $tarball_url..."
    if ! download_file "$tarball_url" "$tarball"; then
        die "Failed to download release. Check if version '$version' exists."
    fi

    info "Extracting..."
    tar -xzf "$tarball" -C "$tmpdir"

    # Move to install directory
    mkdir -p "$(dirname "$INSTALL_DIR")"
    mv "$tmpdir/claude-jail-${version_num}" "$INSTALL_DIR"

    # Cleanup
    rm -rf "$tmpdir"

    success "Installed claude-jail $version to $INSTALL_DIR"
    echo ""

    post_install_message
}

install_from_git() {
    info "Cloning from git..."

    if [[ -d "$INSTALL_DIR" ]]; then
        warn "Existing installation found. Updating..."
        cd "$INSTALL_DIR"
        git pull origin main
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone "https://github.com/${REPO}.git" "$INSTALL_DIR"
    fi

    success "Installed claude-jail from git to $INSTALL_DIR"
    echo ""

    post_install_message
}

post_install_message() {
    echo "Next steps:"
    echo ""
    echo "  1. Add to your ~/.zshrc plugins:"
    echo "     ${GREEN}plugins=(... claude-jail)${NC}"
    echo ""
    echo "  2. Reload your shell:"
    echo "     ${GREEN}source ~/.zshrc${NC}"
    echo ""
    echo "  3. Run Claude in a sandbox:"
    echo "     ${GREEN}claude-jail${NC}"
    echo ""
    echo "For more info: https://github.com/${REPO}"
    echo ""
}

main "$@"
