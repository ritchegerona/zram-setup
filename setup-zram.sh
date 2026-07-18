#!/bin/bash
#
# ZRAM Setup Script - Enhanced Version
# Configures ZRAM swap on multiple Linux distributions
# 
# Author: Ritche Gerona
# License: MIT
#

set -euo pipefail

# Configuration defaults
readonly SCRIPT_NAME="zram-setup"
readonly SCRIPT_VERSION="2.0.0"
readonly LOG_FILE="/var/log/zram-setup.log"

# Default values (can be overridden by interactive prompts)
SWAP_PERCENTAGE="${DEFAULT_SWAP_PERCENTAGE:-50}"
COMPRESSION_ALGO="${DEFAULT_COMPRESSION:-zstd}"
NUM_DEVICES="${DEFAULT_DEVICES:-1}"
DRY_RUN="${DRY_RUN:-false}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    case "$level" in
        ERROR)   echo -e "${RED}❌ $message${NC}" ;;
        SUCCESS) echo -e "${GREEN}✅ $message${NC}" ;;
        WARN)    echo -e "${YELLOW}⚠️  $message${NC}" ;;
        INFO)    echo -e "${BLUE}🔹 $message${NC}" ;;
        *)       echo "$message" ;;
    esac
}

show_help() {
    cat <<EOF
$SCRIPT_NAME v${SCRIPT_VERSION} - ZRAM Swap Configuration Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -s, --size SIZE      Swap size as percentage of RAM (25, 50, 100, or custom)
    -c, --compression ALGO  Compression algorithm (zstd, lz4, lz0)
    -d, --devices NUM    Number of zram devices (1-4)
    -y, --yes            Non-interactive mode, accept defaults
    -n, --dry-run        Preview changes without applying
    -h, --help           Show this help message
    -v, --version        Show version

EXAMPLES:
    $0                      Interactive mode with defaults
    $0 -s 50 -c lz4       50% swap with lz4 compression
    $0 -y                 Non-interactive with defaults
    $0 -n                 Dry-run to preview changes

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--size)
                SWAP_PERCENTAGE="$2"
                shift 2
                ;;
            -c|--compression)
                COMPRESSION_ALGO="$2"
                shift 2
                ;;
            -d|--devices)
                NUM_DEVICES="$2"
                shift 2
                ;;
            -y|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

detect_distro() {
    if [[ -f /etc/debian_version ]]; then
        if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
            DISTRO="ubuntu"
        else
            DISTRO="debian"
        fi
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/rocky-release ]] || [[ -f /etc/alma-release ]]; then
        DISTRO="fedora"
    elif [[ -f /etc/opensuse-release ]] || [[ -f /etc/os-release ]] && grep -qi "opensuse" /etc/os-release; then
        DISTRO="opensuse"
    elif command -v zypper &>/dev/null; then
        DISTRO="opensuse"
    else
        DISTRO="unknown"
    fi
}

validate_swap_percentage() {
    local val="$1"
    if [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 25 ]] && [[ "$val" -le 200 ]]; then
        return 0
    fi
    return 1
}

interactive_prompts() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log INFO "Non-interactive mode enabled, using defaults"
        return
    fi

    echo -e "${BLUE}🌀 ZRAM Setup Configuration${NC}"
    echo ""

    # Swap size selection
    echo "Select swap size (percentage of RAM):"
    echo "  1) 25% - Conservative (minimal swap)"
    echo "  2) 50% - Balanced (default)"
    echo "  3) 100% - Aggressive (swap = RAM size)"
    echo "  4) Custom percentage"
    read -rp "Choice [2]: " swap_choice
    case "${swap_choice:-2}" in
        1) SWAP_PERCENTAGE=25 ;;
        2) SWAP_PERCENTAGE=50 ;;
        3) SWAP_PERCENTAGE=100 ;;
        4)
            read -rp "Enter custom percentage (25-200): " custom_pct
            if validate_swap_percentage "$custom_pct"; then
                SWAP_PERCENTAGE="$custom_pct"
            else
                log ERROR "Invalid percentage, using default 50"
                SWAP_PERCENTAGE=50
            fi
            ;;
        *) SWAP_PERCENTAGE=50 ;;
    esac

    # Compression algorithm selection
    echo ""
    echo "Select compression algorithm:"
    echo "  1) zstd - Best compression ratio (default)"
    echo "  2) lz4 - Fastest compression"
    echo "  3) lz0 - Legacy algorithm"
    read -rp "Choice [1]: " comp_choice
    case "${comp_choice:-1}" in
        1) COMPRESSION_ALGO=zstd ;;
        2) COMPRESSION_ALGO=lz4 ;;
        3) COMPRESSION_ALGO=lz0 ;;
        *) COMPRESSION_ALGO=zstd ;;
    esac

    # Number of devices
    echo ""
    echo "Select number of zram devices (1-4, multiple devices improve performance on multi-core systems):"
    read -rp "Devices [1]: " devices_choice
    if [[ "$devices_choice" =~ ^[1-4]$ ]]; then
        NUM_DEVICES="$devices_choice"
    fi
}

detect_existing_swap() {
    local has_swap=false
    local swap_devices=()
    
    # Check for swap files/partitions
    while read -r line; do
        if [[ "$line" != "Filename" ]] && [[ -n "$line" ]]; then
            has_swap=true
            swap_devices+=("$line")
        fi
    done < <(awk '{print $1}' /proc/swaps 2>/dev/null || true)

    if [[ "$has_swap" == "true" ]] && [[ ${#swap_devices[@]} -gt 0 ]]; then
        log WARN "Existing swap detected: ${swap_devices[*]}"
        return 0
    fi
    return 1
}

disable_existing_swap() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would disable existing swap"
        return
    fi

    log INFO "Disabling existing swap..."
    swapon --show | awk '{print $1}' | while read -r swap_dev; do
        [[ -n "$swap_dev" ]] && sudo swapoff "$swap_dev" 2>/dev/null || true
    done
    
    # Backup fstab entries with swap
    if [[ -f /etc/fstab ]]; then
        sudo cp /etc/fstab "/etc/fstab.backup.zram.$(date +%s)" 2>/dev/null || true
        # Comment out swap entries in fstab
        sudo sed -i.bak 's/^\([^#].*swap[^#]*\)/#\1/' /etc/fstab
    fi
    log SUCCESS "Existing swap disabled and fstab backed up"
}

setup_debian() {
    log INFO "Setting up ZRAM on Debian/Ubuntu..."
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would install zram-tools" || sudo apt update && sudo apt install -y zram-tools
    
    local config_file="/etc/default/zramswap"
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would configure $config_file" || {
        sudo tee "$config_file" > /dev/null <<EOF
ENABLED=true
PERCENT=${SWAP_PERCENTAGE}
ALGO=${COMPRESSION_ALGO}
DEVICES=${NUM_DEVICES}
EOF
    }
    
    configure_sysctl
    enable_service "zramswap.service"
}

setup_arch() {
    log INFO "Setting up ZRAM on Arch Linux..."
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would install systemd-zram-generator" || {
        sudo pacman -Syu --noconfirm systemd zram-generator
    }
    
    setup_zram_generator
    configure_sysctl
    
    # Enable the service
    for i in $(seq 0 $((NUM_DEVICES - 1))); do
        enable_service "systemd-zram-setup@zram${i}.service"
    done
}

setup_fedora() {
    log INFO "Setting up ZRAM on Fedora/RHEL..."
    
    if command -v dnf &>/dev/null; then
        pkg_mgr="dnf"
    elif command -v yum &>/dev/null; then
        pkg_mgr="yum"
    else
        pkg_mgr="dnf" # Default
    fi

    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would install systemd-zram-generator" || {
        sudo "$pkg_mgr" install -y systemd-zram-generator
    }
    
    setup_zram_generator
    configure_sysctl
    
    for i in $(seq 0 $((NUM_DEVICES - 1))); do
        enable_service "systemd-zram-setup@zram${i}.service"
    done
}

setup_opensuse() {
    log INFO "Setting up ZRAM on openSUSE..."
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would install systemd-zram-generator" || {
        sudo zypper refresh
        sudo zypper -n install systemd-zram-generator
    }
    
    setup_zram_generator
    configure_sysctl
    
    for i in $(seq 0 $((NUM_DEVICES - 1))); do
        enable_service "systemd-zram-setup@zram${i}.service" 2>/dev/null || log WARN "Service may need manual enable on openSUSE"
    done
}

configure_sysctl() {
    local sysctl_file="/etc/sysctl.d/99-zram.conf"
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would configure $sysctl_file" || {
        sudo tee "$sysctl_file" > /dev/null <<EOF
vm.swappiness=100
vm.vfs_cache_pressure=50
EOF
        sudo sysctl -p "$sysctl_file" 2>/dev/null || true
    }
}

setup_zram_generator() {
    sudo mkdir -p /etc/systemd
    local generator_conf="/etc/systemd/zram-generator.conf"
    
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would configure $generator_conf for ${NUM_DEVICES} device(s)" || {
        local config_content=""
        for i in $(seq 0 $((NUM_DEVICES - 1))); do
            config_content+="[zram${i}]
zram-size = ram / ${SWAP_PERCENTAGE} * ${NUM_DEVICES}
compression-algorithm = ${COMPRESSION_ALGO}

"
        done
        echo "$config_content" | sudo tee "$generator_conf" > /dev/null
    }
    
    if [[ "$DRY_RUN" != "true" ]]; then
        sudo systemctl daemon-reload 2>/dev/null || true
    fi
}

enable_service() {
    local service="$1"
    [[ "$DRY_RUN" == "true" ]] && log INFO "DRY RUN: Would enable $service" || {
        sudo systemctl enable --now "$service" 2>/dev/null || log WARN "Could not enable $service - may need manual setup"
    }
}

verify_setup() {
    log INFO "Verifying ZRAM setup..."
    echo ""
    echo "Current swap devices:"
    cat /proc/swaps 2>/dev/null || echo "No swap found"
    echo ""
    echo "Memory usage:"
    free -h 2>/dev/null || true
    echo ""
    echo "ZRAM devices:"
    zramctl 2>/dev/null || true
    
    if command -v swapon &>/dev/null; then
        echo ""
        echo "Active swap:"
        swapon --show 2>/dev/null || echo "No active swap"
    fi
}

main() {
    # Initialize log file
    touch "$LOG_FILE" 2>/dev/null || true
    
    log INFO "Starting $SCRIPT_NAME v${SCRIPT_VERSION}..."
    
    # Check for root
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi

    # Parse command line arguments
    parse_args "$@"

    # Detect distribution
    detect_distro
    log INFO "Detected distribution: $DISTRO"

    [[ "$DISTRO" == "unknown" ]] && {
        log ERROR "Unsupported distribution. Supported: Debian/Ubuntu, Arch, Fedora/RHEL, openSUSE"
        exit 1
    }

    # Interactive prompts if needed
    interactive_prompts

    log INFO "Configuration: ${SWAP_PERCENTAGE}% swap, ${COMPRESSION_ALGO} compression, ${NUM_DEVICES} device(s)"

    # Detect and disable existing swap
    if detect_existing_swap; then
        log WARN "Existing swap will be disabled for ZRAM-only setup"
        disable_existing_swap
    fi

    # Setup based on distribution
    case "$DISTRO" in
        debian|ubuntu) setup_debian ;;
        arch) setup_arch ;;
        fedora) setup_fedora ;;
        opensuse) setup_opensuse ;;
    esac

    # Verify setup
    verify_setup

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN complete - no changes were applied"
    else
        log SUCCESS "ZRAM setup complete!"
    fi

    exit 0
}

# Run main function
main "$@"