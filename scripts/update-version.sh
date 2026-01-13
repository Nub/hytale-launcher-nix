#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
readonly FLATPAK_URL="https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak"
readonly PACKAGE_FILE="package.nix"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# === Logging Functions (output to stderr to not interfere with function returns) ===
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# === Version/Hash Extraction ===
get_current_hash() {
    # Extract SRI hash from package.nix
    sed -n 's/.*sha256 = "\(sha256-[^"]*\)".*/\1/p' "$PACKAGE_FILE" | head -1
}

get_current_version() {
    # Extract version from package.nix
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$PACKAGE_FILE" | head -1
}

# === Hash Computation ===
fetch_latest_hash() {
    # Use nix-prefetch-url to get hash of the flatpak
    log_info "Fetching latest flatpak from upstream..."

    # Get the raw base32 hash first
    local raw_hash
    raw_hash=$(nix-prefetch-url --quiet "$FLATPAK_URL" 2>/dev/null)

    if [ -z "$raw_hash" ]; then
        log_error "Failed to fetch flatpak hash"
        return 1
    fi

    # Convert base32 to SRI format (sha256-base64)
    local sri_hash
    sri_hash=$(nix hash convert --hash-algo sha256 --to sri "$raw_hash" 2>/dev/null)

    echo "$sri_hash"
}

# === Update Functions ===
generate_new_version() {
    # Date-based versioning: YYYY.MM.DD
    date +"%Y.%m.%d"
}

update_package_hash() {
    local new_hash="$1"
    sed -i.bak "s|sha256 = \"sha256-[^\"]*\"|sha256 = \"$new_hash\"|" "$PACKAGE_FILE"
}

update_package_version() {
    local new_version="$1"
    sed -i.bak "s|version = \"[^\"]*\"|version = \"$new_version\"|" "$PACKAGE_FILE"
}

cleanup_backups() {
    rm -f "${PACKAGE_FILE}.bak"
}

restore_from_backup() {
    if [ -f "${PACKAGE_FILE}.bak" ]; then
        mv "${PACKAGE_FILE}.bak" "$PACKAGE_FILE"
        log_info "Restored package.nix from backup"
    fi
}

# === Validation ===
verify_build() {
    log_info "Verifying build..."
    if nix build .#hytale-launcher --no-link 2>&1; then
        log_info "Build verification passed"
        return 0
    else
        log_error "Build verification failed"
        return 1
    fi
}

ensure_in_repository_root() {
    if [ ! -f "flake.nix" ] || [ ! -f "$PACKAGE_FILE" ]; then
        log_error "flake.nix or $PACKAGE_FILE not found. Run from repository root."
        exit 1
    fi
}

ensure_required_tools() {
    command -v nix >/dev/null 2>&1 || { log_error "nix is required"; exit 1; }
    command -v nix-prefetch-url >/dev/null 2>&1 || { log_error "nix-prefetch-url is required"; exit 1; }
}

# === CLI Interface ===
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Hytale Launcher Nix package updater. Detects new versions via hash comparison.

Options:
  --check       Only check for updates, don't apply (exit 1 if update available)
  --force       Force update even if hashes match
  --help        Show this help message

Examples:
  $0              # Check and apply updates
  $0 --check      # CI mode: check only, exit 1 if update needed
  $0 --force      # Force regenerate version (e.g., after flake.lock update)
EOF
}

# === Main Logic ===
main() {
    local check_only=false
    local force_update=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                check_only=true
                shift
                ;;
            --force)
                force_update=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    ensure_in_repository_root
    ensure_required_tools

    local current_version
    current_version=$(get_current_version)
    local current_hash
    current_hash=$(get_current_hash)

    log_info "Current version: $current_version"
    log_info "Current hash: $current_hash"

    local latest_hash
    latest_hash=$(fetch_latest_hash)

    if [ -z "$latest_hash" ]; then
        log_error "Failed to fetch latest hash"
        exit 1
    fi

    log_info "Latest hash: $latest_hash"

    # Compare hashes
    if [ "$current_hash" = "$latest_hash" ] && [ "$force_update" = false ]; then
        log_info "Already up to date!"
        exit 0
    fi

    local new_version
    new_version=$(generate_new_version)

    # Handle same-day updates (append .N suffix)
    if [ "$current_hash" != "$latest_hash" ]; then
        # Extract base date from current version (handle 2025.01.14 and 2025.01.14.2)
        local current_base_date
        current_base_date=$(echo "$current_version" | grep -oE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}')

        if [ "$current_base_date" = "$new_version" ]; then
            # Same day - need suffix
            local current_suffix
            current_suffix=$(echo "$current_version" | grep -oE '\.[0-9]+$' | tr -d '.' || echo "0")

            if [ -z "$current_suffix" ] || [ "$current_suffix" = "0" ]; then
                # First update today was base version, next is .2
                new_version="${new_version}.2"
            else
                # Increment suffix
                local next_suffix=$((current_suffix + 1))
                new_version="${new_version}.${next_suffix}"
            fi
        fi
    fi

    log_info "Update available: $current_version ($current_hash) -> $new_version ($latest_hash)"

    if [ "$check_only" = true ]; then
        # Output for GitHub Actions
        echo "UPDATE_AVAILABLE=true"
        echo "CURRENT_VERSION=$current_version"
        echo "NEW_VERSION=$new_version"
        echo "CURRENT_HASH=$current_hash"
        echo "NEW_HASH=$latest_hash"
        exit 1  # Non-zero indicates update available
    fi

    # Apply updates
    log_info "Applying update..."
    update_package_version "$new_version"
    update_package_hash "$latest_hash"

    # Verify build
    if ! verify_build; then
        log_error "Build failed, restoring backup..."
        restore_from_backup
        exit 1
    fi

    cleanup_backups

    log_info "Successfully updated from $current_version to $new_version"

    # Update flake.lock
    log_info "Updating flake.lock..."
    nix flake update 2>&1 || true

    # Show changes
    echo ""
    log_info "Changes applied:"
    git diff --stat "$PACKAGE_FILE" flake.lock 2>/dev/null || true
}

main "$@"
