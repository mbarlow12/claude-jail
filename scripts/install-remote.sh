#!/usr/bin/env bash
# Remote installer for claude-jail
# Usage: curl -fsSL https://raw.githubusercontent.com/mbarlow12/claude-jail/main/scripts/install-remote.sh | bash
#
# Environment variables:
#   CJ_VERSION    - Install specific version (e.g., "0.1.0"), default: latest
#   CJ_INSTALL_DIR - Override install directory

set -euo pipefail

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { error "$*"; exit 1; }

REPO="mbarlow12/claude-jail"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

# Detect download tool
detect_downloader() {
    if command -v curl &>/dev/null; then
        echo "curl"
    elif command -v wget &>/dev/null; then
        echo "wget"
    else
        die "Neither curl nor wget found. Please install one of them."
    fi
}

# Download a URL to stdout
download() {
    local url="$1"
    local downloader
    downloader=$(detect_downloader)

    case "$downloader" in
        curl) curl -fsSL "$url" ;;
        wget) wget -qO- "$url" ;;
    esac
}

# Download a URL to a file
download_file() {
    local url="$1"
    local dest="$2"
    local downloader
    downloader=$(detect_downloader)

    case "$downloader" in
        curl) curl -fsSL -o "$dest" "$url" ;;
        wget) wget -q -O "$dest" "$url" ;;
    esac
}

# Get latest version from GitHub API
get_latest_version() {
    local response
    response=$(download "$GITHUB_API" 2>/dev/null) || die "Failed to fetch latest release from GitHub"

    # Parse tag_name from JSON (simple grep, no jq dependency)
    echo "$response" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/'
}

# Detect shell environment
detect_shell_env() {
    # Check for Oh My Zsh
    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        echo "omz"
        return
    fi

    # Check current shell
    local current_shell
    current_shell=$(basename "${SHELL:-/bin/bash}")

    if [[ "$current_shell" == "zsh" ]]; then
        echo "zsh"
    else
        echo "bash"
    fi
}

# Get default install directory based on shell environment
get_install_dir() {
    local shell_env="$1"

    if [[ -n "${CJ_INSTALL_DIR:-}" ]]; then
        echo "$CJ_INSTALL_DIR"
        return
    fi

    case "$shell_env" in
        omz)
            echo "${HOME}/.oh-my-zsh/custom/plugins/claude-jail"
            ;;
        *)
            echo "${HOME}/.local/share/claude-jail"
            ;;
    esac
}

# Get shell rc file
get_rc_file() {
    local shell_env="$1"

    case "$shell_env" in
        omz|zsh)
            echo "${HOME}/.zshrc"
            ;;
        *)
            echo "${HOME}/.bashrc"
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v bwrap &>/dev/null; then
        missing+=("bubblewrap")
    fi

    if ! command -v tar &>/dev/null; then
        missing+=("tar")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install on Debian/Ubuntu:"
        echo "  sudo apt install ${missing[*]}"
        echo ""
        echo "Install on Fedora:"
        echo "  sudo dnf install ${missing[*]}"
        echo ""
        echo "Install on Arch:"
        echo "  sudo pacman -S ${missing[*]}"
        exit 1
    fi
}

# Prompt for yes/no
prompt_yn() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ ! -t 0 ]]; then
        # Non-interactive, use default
        [[ "$default" == "y" ]]
        return
    fi

    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n] " response
        [[ -z "$response" || "$response" =~ ^[Yy] ]]
    else
        read -r -p "$prompt [y/N] " response
        [[ "$response" =~ ^[Yy] ]]
    fi
}

# Generate shell configuration snippet
generate_config_snippet() {
    local shell_env="$1"
    local install_dir="$2"

    case "$shell_env" in
        omz)
            # Oh My Zsh - just need to add to plugins array
            echo "# Add 'claude-jail' to your plugins array in ~/.zshrc:"
            echo "# plugins=(... claude-jail)"
            ;;
        zsh)
            # Plain zsh - source the plugin
            cat <<EOF
# claude-jail
source "${install_dir}/claude-jail.plugin.zsh"
EOF
            ;;
        *)
            # Bash - add bin to PATH
            cat <<EOF
# claude-jail
export PATH="\$PATH:${install_dir}/bin"
EOF
            ;;
    esac
}

main() {
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║       claude-jail installer           ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    # Check dependencies
    info "Checking dependencies..."
    check_dependencies
    success "Dependencies satisfied"

    # Detect environment
    local shell_env
    shell_env=$(detect_shell_env)
    info "Detected shell environment: $shell_env"

    # Determine version
    local version
    if [[ -n "${CJ_VERSION:-}" ]]; then
        version="$CJ_VERSION"
        info "Using specified version: $version"
    else
        info "Fetching latest version..."
        version=$(get_latest_version)
        [[ -n "$version" ]] || die "Failed to determine latest version"
        success "Latest version: $version"
    fi

    # Determine install directory
    local install_dir
    install_dir=$(get_install_dir "$shell_env")
    info "Install directory: $install_dir"

    # Check for existing installation
    if [[ -d "$install_dir" ]]; then
        if [[ -f "$install_dir/VERSION" ]]; then
            local current_version
            current_version=$(cat "$install_dir/VERSION")
            warn "Existing installation found: v$current_version"
        else
            warn "Existing installation found (unknown version)"
        fi

        if ! prompt_yn "Overwrite existing installation?" "y"; then
            info "Installation cancelled"
            exit 0
        fi
    fi

    # Download and extract
    local archive_url="https://github.com/${REPO}/releases/download/v${version}/claude-jail-${version}.tar.gz"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    info "Downloading claude-jail v${version}..."
    download_file "$archive_url" "$tmp_dir/archive.tar.gz" || die "Failed to download release archive"
    success "Download complete"

    info "Extracting..."
    tar -xzf "$tmp_dir/archive.tar.gz" -C "$tmp_dir" || die "Failed to extract archive"

    # Install
    info "Installing to $install_dir..."
    mkdir -p "$(dirname "$install_dir")"
    rm -rf "$install_dir"
    mv "$tmp_dir/claude-jail-${version}" "$install_dir"

    # Make scripts executable
    chmod +x "$install_dir/bin/"* 2>/dev/null || true
    chmod +x "$install_dir/install.sh" 2>/dev/null || true

    success "Installation complete!"
    echo ""

    # Shell configuration
    local rc_file
    rc_file=$(get_rc_file "$shell_env")

    if [[ "$shell_env" == "omz" ]]; then
        # Oh My Zsh - just instructions
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│ Add 'claude-jail' to your plugins array in ~/.zshrc:   │"
        echo "│                                                         │"
        echo "│   plugins=(... claude-jail)                             │"
        echo "│                                                         │"
        echo "│ Then reload: source ~/.zshrc                            │"
        echo "└─────────────────────────────────────────────────────────┘"
    else
        local snippet
        snippet=$(generate_config_snippet "$shell_env" "$install_dir")

        echo "To use claude-jail, add the following to $rc_file:"
        echo ""
        echo "$snippet"
        echo ""

        if prompt_yn "Add this to $rc_file now?" "y"; then
            echo "" >> "$rc_file"
            echo "$snippet" >> "$rc_file"
            success "Added to $rc_file"
            echo ""
            echo "Reload your shell: source $rc_file"
        else
            info "Skipped. Add manually when ready."
        fi
    fi

    echo ""
    success "claude-jail v${version} installed successfully!"
    echo ""
    echo "Quick start:"
    echo "  claude-jail              # Run in current directory"
    echo "  claude-jail -p paranoid  # Maximum isolation"
    echo "  claude-jail --help       # See all options"
    echo ""
}

main "$@"
