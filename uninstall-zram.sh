#!/bin/bash
#
# ZRAM Uninstall Script - Cleanup ZRAM configuration
# 
# Author: Ritche Gerona
# License: MIT
#

set -euo pipefail

readonly SCRIPT_VERSION="2.0.0"
DRY_RUN="${DRY_RUN:-false}"
RESTORE_SWAP="${RESTORE_SWAP:-true}"

log() {
    local level="$1"
    shift
    local message="$*"
    case "$level" in
        ERROR)   echo -e "\033[0;31m❌ $message\033[0m" ;;
        SUCCESS) echo -e "\033[0;32m✅ $message\033[0m" ;;
        WARN)    echo -e "\033[1;33m⚠️  $message\033[0m" ;;
        INFO)    echo -e "\033[0;34m🔹 $message\033[0m" ;;
        *)       echo "$message" ;;
    esac
}

detect_distro() {
    if [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
    elif [[ -f /etc/fedora-release ]] || [[ -f /etc/rocky-release ]] || [[ -f /etc/alma-release ]]; then
        DISTRO="fedora"
    elif [[ -f /etc/opensuse-release ]] || command -v zypper &>/dev/null; then
        DISTRO="opensuse"
    else
        DISTRO="unknown"
    fi
}

stop_zram_services() {
    log INFO "Stopping ZRAM services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would stop zram services"
        return
    fi

    # Stop systemd-based zram
    for service in systemd-zram-setup@zram*.service zramswap.service; do
        if systemctl list-unit-files "$service" &>/dev/null; then
            sudo systemctl stop "$service" 2>/dev/null || true
        fi
    done

    # Disable services
    for service in systemd-zram-setup@zram*.service zramswap.service; do
        if systemctl list-unit-files "$service" &>/dev/null; then
            sudo systemctl disable "$service" 2>/dev/null || true
        fi
    done
}

remove_config_files() {
    log INFO "Removing configuration files..."

    local files=(
        "/etc/default/zramswap"
        "/etc/systemd/zram-generator.conf"
        "/etc/sysctl.d/99-zram.conf"
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would remove config files"
        for f in "${files[@]}"; do
            sudo rm -f "$f" 2>/dev/null && log INFO "  Would remove: $f"
        done
        return
    fi

    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            sudo rm -f "$f" && log SUCCESS "  Removed: $f"
        fi
    done
}

restore_swap() {
    if [[ "$RESTORE_SWAP" != "true" ]]; then
        return
    fi

    log INFO "Checking for swap backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would restore swap if backup exists"
        return
    fi

    # Find fstab backup
    local backup_file
    backup_file=$(ls /etc/fstab.backup.zram.* 2>/dev/null | head -1) || true

    if [[ -n "$backup_file" ]]; then
        log INFO "Restoring swap from backup: $backup_file"
        sudo cp "$backup_file" /etc/fstab
        log SUCCESS "Swap configuration restored"
    else
        log WARN "No swap backup found, manual swap reconfiguration may be needed"
    fi
}

remove_packages() {
    log INFO "Optionally removing ZRAM packages..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN: Would offer package removal"
        return
    fi

    echo ""
    read -rp "Remove zram-tools packages? (y/N): " remove_pkgs
    if [[ "$remove_pkgs" =~ ^[Yy]$ ]]; then
        case "$DISTRO" in
            debian) sudo apt purge -y zram-tools zram-generator ;;
            arch) sudo pacman -Rns --noconfirm systemd-zram-generator 2>/dev/null || true ;;
            fedora) sudo dnf remove -y systemd-zram-generator 2>/dev/null || true ;;
            opensuse) sudo zypper -n remove systemd-zram-generator 2>/dev/null || true ;;
        esac
        log SUCCESS "Packages removed"
    fi
}

main() {
    log INFO "ZRAM Uninstall Script v${SCRIPT_VERSION}"

    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        log ERROR "This script must be run as root (use sudo)"
        exit 1
    fi

    detect_distro
    log INFO "Detected distribution: $DISTRO"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN MODE - No changes will be applied"
    fi

    # Confirm action
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        read -rp "This will remove ZRAM configuration. Continue? (y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && log INFO "Aborted" && exit 0
    fi

    stop_zram_services
    remove_config_files
    restore_swap
    remove_packages

    log SUCCESS "ZRAM uninstallation complete!"
    log INFO "Verify swap with: cat /proc/swaps && free -h"
}

main "$@"