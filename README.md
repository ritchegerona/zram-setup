[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://github.com/ritchegerona/zram-setup/workflows/ShellCheck/badge.svg)](https://github.com/ritchegerona/zram-setup/actions)
![Last Commit](https://img.shields.io/github/last-commit/ritchegerona/zram-setup)
![Stars](https://img.shields.io/github/stars/ritchegerona/zram-setup?style=social)

# 🌀 ZRAM Setup for Linux

<p align="center">
  <img src="logo.png" alt="ZRAM Logo" width="300"/>
</p>

Configure **ZRAM swap** on multiple Linux distributions. Boosts performance, reduces SSD wear, and optimizes memory using compressed RAM swap.

## Features

- Multi-distro support: Debian/Ubuntu, Arch Linux, Fedora/RHEL, openSUSE
- Interactive configuration with sensible defaults
- Automatic detection and disabling of existing swap
- Multiple swap size options (25%, 50%, 100%, or custom)
- Multiple compression algorithms (zstd, lz4, lz0)
- Multi-device support for better multi-core performance
- Dry-run mode to preview changes
- Uninstall script to cleanly remove configuration
- Logging to `/var/log/zram-setup.log`

## 📦 Installation

```bash
git clone https://github.com/ritchegerona/zram-setup.git
cd zram-setup
chmod +x setup-zram.sh uninstall-zram.sh
```

## ▶️ Usage

### Interactive Mode (recommended)
```bash
sudo ./setup-zram.sh
```

### Non-interactive Mode
```bash
sudo ./setup-zram.sh -y
```

### Custom Configuration
```bash
# Set swap size to 50% with lz4 compression
sudo ./setup-zram.sh -s 50 -c lz4

# Dry-run to preview changes
./setup-zram.sh -n
```

### Command-line Options
| Option | Description |
|--------|-----------|
| `-s, --size SIZE` | Swap size as percentage of RAM (25, 50, 100, or custom) |
| `-c, --compression ALGO` | Compression algorithm: zstd, lz4, lz0 |
| `-d, --devices NUM` | Number of zram devices (1-4) |
| `-y, --yes` | Non-interactive mode, accept defaults |
| `-n, --dry-run` | Preview changes without applying |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |

## ✅ Verification

After running the setup, verify ZRAM is working:

```bash
# Check swap devices
cat /proc/swaps

# Check memory usage
free -h

# Check ZRAM devices specifically
zramctl
```

## 🧹 Uninstall/Rollback

To remove ZRAM configuration and optionally restore disk swap:

```bash
sudo ./uninstall-zram.sh
```

The uninstall script will:
- Stop and disable ZRAM services
- Remove configuration files
- Restore original swap from backup (if available)
- Optionally remove installed packages

## 🔧 Troubleshooting

### Swap not enabled after reboot
```bash
# Check service status
systemctl status zramswap.service    # Debian/Ubuntu
systemctl status systemd-zram-setup@zram0.service  # Arch/Fedora/openSUSE

# Reload systemd daemon
sudo systemctl daemon-reload
```

### Check compression algorithm available
```bash
# List available algorithms
zcat -h 2>&1 | grep -o -E '^[a-z0-9]+'

# Or check kernel config
grep CONFIG_ZRAM_DEF_COMP /boot/config-$(uname -r)
```

### Performance tuning
Add to `/etc/sysctl.d/99-zram.conf`:
```
vm.swappiness=100        # Aggressive swapping to ZRAM
vm.vfs_cache_pressure=50   # Balance file cache vs app memory
```

## 📜 License

This project is licensed under the MIT License - see [LICENSE.md](LICENSE.md) for details.

## 🙏 Acknowledgments

- Inspired by zram-generator documentation
- Tested on Debian 12, Ubuntu 24.04, Arch Linux, Fedora 40