# Arch + CachyOS Plasma Setup

Post-install script for a minimal, CLI-only Arch Linux installation. It uses `pacman` only—no `paru` or `yay`.

## Before You Start

- Use a fresh Arch Linux installation.
- Create a normal user with working `sudo` access.
- Run the script as that normal user, **not** as root.
- Review the script before running it. It changes packages, services, boot settings, zram, udev rules, `/etc/fstab`, systemd timeouts, and your default shell.
- Back up important data first.

## 1. Install Minimal Arch

Boot the Arch ISO and run:

```bash
archinstall
```

Recommended choices:

- Profile: **Minimal**
- Bootloader: **systemd-boot**
- Network: **NetworkManager**
- Audio: leave unconfigured; the script installs PipeWire
- Additional packages: `sudo git networkmanager`
- Create a normal administrator user

Complete the installation, reboot, and log in as your normal user.

## 2. Clone and Run

Clone over SSH:

```bash
git clone git@github.com:Sn0whax/Archtips.git
cd Archtips
chmod +x arch-cachy-setup.sh
less arch-cachy-setup.sh
./arch-cachy-setup.sh
```

For a public HTTPS clone instead:

```bash
git clone https://github.com/Sn0whax/Archtips.git
```

Do **not** run the whole script with `sudo`; it uses `sudo` internally where required.

## Optional Environment Variables

Skip NAS setup:

```bash
SETUP_NAS=no ./arch-cachy-setup.sh
```

Configure a different NAS share:

```bash
NAS_SHARE='//192.168.1.10/dox' NAS_MOUNT='/mnt/nas' SETUP_NAS=yes ./arch-cachy-setup.sh
```

Install or skip the NVIDIA open kernel module without prompting:

```bash
INSTALL_NVIDIA_OPEN=yes ./arch-cachy-setup.sh
INSTALL_NVIDIA_OPEN=no ./arch-cachy-setup.sh
```

## What It Does

- Adds the official CachyOS repositories
- Installs KDE Plasma and Plasma Login Manager
- Installs the CachyOS kernel and headers
- Optionally installs `linux-cachyos-nvidia-open`
- Installs the configured applications using `pacman`
- Enables NetworkManager, Plasma Login Manager, AppArmor, and LACT when available
- Attempts to make the CachyOS systemd-boot entry the default
- Configures the PowerDevil DDC/CI environment override
- Configures LZ4 zram
- Selects ADIOS for supported NVMe devices
- Optionally configures the CIFS NAS automount and protected credentials file
- Reduces systemd stop and abort timeouts
- Removes selected unwanted packages when installed
- Changes the login shell to fish and adds personal aliases
- Reports and skips packages missing from enabled pacman repositories

## Reboot and Verify

```bash
sudo reboot
```

After rebooting:

```bash
uname -r
swapon --show
bootctl status
systemctl status NetworkManager plasmalogin apparmor
cat /sys/block/nvme0n1/queue/scheduler
getent passwd "$USER" | cut -d: -f7
```

## Troubleshooting

Test GitHub SSH access:

```bash
ssh -T git@github.com
```

Check a skipped package:

```bash
pacman -Si package-name
```

Inspect Plasma Login Manager:

```bash
systemctl status plasmalogin.service
journalctl -b -u plasmalogin.service
```

List and select systemd-boot entries:

```bash
bootctl list
sudo bootctl set-default ENTRY-ID
```

## Security

NAS credentials are written to `/etc/samba/credentials/share` as `root:root` with mode `0600`. Never commit NAS passwords, tokens, or SSH private keys.

## Disclaimer

This is personal installation automation provided without warranty. Read and understand the script before using it.
