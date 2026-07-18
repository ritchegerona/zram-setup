# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-07-18

### Added
- **Interactive configuration prompts** - Users can now select swap size, compression algorithm, and number of devices at runtime
- **Command-line arguments**:
  - `-s, --size` - Swap size as percentage of RAM (25, 50, 100, or custom)
  - `-c, --compression` - Compression algorithm (zstd, lz4, lz0)
  - `-d, --devices` - Number of zram devices (1-4)
  - `-y, --yes` - Non-interactive mode
  - `-n, --dry-run` - Preview changes without applying
  - `-h, --help` - Show help message
  - `-v, --version` - Show version
- **Multi-distro support**: Fedora, Rocky Linux, AlmaLinux, and openSUSE
- **Automatic swap detection** - Script detects and disables existing swap automatically
- **Logging** - All actions logged to `/var/log/zram-setup.log`
- **Uninstall script** - `uninstall-zram.sh` for clean removal with swap restoration

### Changed
- Switched from `set -e` to `set -euo pipefail` for better error handling
- Moved workflow from `workflows/` to `.github/workflows/` (correct path)
- Improved README with comprehensive documentation, tables, and troubleshooting section

### Fixed
- Proper root privilege check at script start
- Function-based code structure for better maintainability