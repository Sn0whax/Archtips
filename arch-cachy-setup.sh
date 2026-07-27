#!/usr/bin/env bash
# arch-cachy-setup.sh - post-install setup for a minimal Arch Linux system
# Run as your normal user: bash arch-cachy-setup.sh
set -Eeuo pipefail
IFS=$'\n\t'

[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not as root." >&2; exit 1; }
command -v sudo >/dev/null || { echo "sudo is required." >&2; exit 1; }
sudo -v

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
trap 'warn "Failed at line $LINENO: $BASH_COMMAND"' ERR

# Change these before running, or provide them as environment variables.
NAS_SHARE="${NAS_SHARE:-//192.168.1.10/dox}"
NAS_MOUNT="${NAS_MOUNT:-/mnt/nas}"
NAS_UID="${NAS_UID:-$(id -u)}"
NAS_GID="${NAS_GID:-$(id -g)}"
SETUP_NAS="${SETUP_NAS:-ask}"              # ask, yes, or no
INSTALL_NVIDIA_OPEN="${INSTALL_NVIDIA_OPEN:-ask}" # ask, yes, or no

log "Refreshing package databases and installing bootstrap tools"
sudo pacman -Syu --needed --noconfirm git curl tar

log "Adding the official CachyOS repositories"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 \
  https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$tmpdir/cachyos-repo.tar.xz"
tar -xJf "$tmpdir/cachyos-repo.tar.xz" -C "$tmpdir"
repo_script="$(find "$tmpdir" -type f -name cachyos-repo.sh -print -quit)"
[[ -n "$repo_script" ]] || { echo "cachyos-repo.sh was not found in the archive." >&2; exit 1; }
sudo bash "$repo_script"
sudo pacman -Syyu --noconfirm

# pacman only: unavailable names are reported and skipped rather than aborting everything.
install_available() {
  local available=() missing=() pkg
  for pkg in "$@"; do
    if pacman -Si -- "$pkg" >/dev/null 2>&1; then available+=("$pkg"); else missing+=("$pkg"); fi
  done
  ((${#available[@]})) && sudo pacman -S --needed --noconfirm -- "${available[@]}"
  ((${#missing[@]})) && warn "Not found in enabled pacman repositories; skipped: ${missing[*]}"
}

REQUIRED_PACKAGES=(
  plasma-meta plasma-login-manager konsole dolphin ark kate spectacle
  xdg-desktop-portal-kde networkmanager pipewire pipewire-alsa pipewire-pulse wireplumber
  systemd-boot-manager zram-generator
  cachyos-settings cachyos-hello linux-cachyos linux-cachyos-headers
  python-pynvml fish nano alsa-utils apparmor cifs-utils ufw
)

OPTIONAL_PACKAGES=(
  proton-cachyos-slr wine-cachyos btop cava xorg-xwininfo
  steam okular kcalc protonup-qt fastfetch
  ttf-migu ttf-hack-nerd ttf-baekmuk obs-studio brave-origin-bin
  discord mpv audacious haruna signal-desktop lact faugus-launcher
  phonon-qt6-mpv-git yt-dlp
)

log "Installing required Plasma, CachyOS kernel, and system packages"
sudo pacman -S --needed --noconfirm -- "${REQUIRED_PACKAGES[@]}"

log "Installing optional requested packages"
install_available "${OPTIONAL_PACKAGES[@]}"

if [[ "$INSTALL_NVIDIA_OPEN" == ask ]]; then
  read -r -p "Install linux-cachyos-nvidia-open for a supported NVIDIA GPU? [y/N] " answer
  [[ ${answer,,} == y || ${answer,,} == yes ]] && INSTALL_NVIDIA_OPEN=yes || INSTALL_NVIDIA_OPEN=no
fi
[[ "$INSTALL_NVIDIA_OPEN" == yes ]] && install_available linux-cachyos-nvidia-open

log "Enabling AppArmor profile caching"
sudo install -d -m 0755 /etc/apparmor/earlypolicy
for directive in \
  'write-cache' \
  'Optimize=compress-fast' \
  'cache-loc /etc/apparmor/earlypolicy/'
do
  sudo grep -qxF "$directive" /etc/apparmor/parser.conf || printf '%s\n' "$directive" | sudo tee -a /etc/apparmor/parser.conf >/dev/null
done

if command -v sdboot-manage >/dev/null 2>&1 && [[ -f /etc/sdboot-manage.conf ]]; then
  log "Configuring systemd-boot kernel parameters"
  linux_options='LINUX_OPTIONS="zswap.enabled=0 nowatchdog nmi_watchdog=0 split_lock_detect=off lsm=landlock,lockdown,yama,integrity,apparmor,bpf"'
  if sudo grep -qE '^[#[:space:]]*LINUX_OPTIONS=' /etc/sdboot-manage.conf; then
    sudo sed -Ei "s|^[#[:space:]]*LINUX_OPTIONS=.*|${linux_options}|" /etc/sdboot-manage.conf
  else
    printf '%s\n' "$linux_options" | sudo tee -a /etc/sdboot-manage.conf >/dev/null
  fi
  sudo sdboot-manage gen
else
  warn "sdboot-manage is unavailable; kernel options were not changed."
fi

log "Configuring UFW firewall"
sudo systemctl enable ufw.service
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable
sudo ufw status verbose

log "Removing SDDM if installed"
if pacman -Q sddm >/dev/null 2>&1; then
  sudo systemctl disable sddm.service 2>/dev/null || true
  sudo pacman -Rns --noconfirm sddm || warn "SDDM could not be removed automatically."
fi

log "Enabling desktop and security services"
sudo systemctl enable NetworkManager.service plasmalogin.service apparmor.service
# LACT supplies this service on current packages; do not fail if its name changes.
sudo systemctl enable lactd.service 2>/dev/null || warn "lactd.service was not found; configure LACT manually if needed."

log "Making the CachyOS systemd-boot entry the default when discoverable"
if bootctl is-installed >/dev/null 2>&1; then
  entry="$(find /boot/loader/entries -maxdepth 1 -type f -iname '*cachy*.conf' -printf '%f\n' 2>/dev/null | sort | head -n1 || true)"
  if [[ -n "$entry" ]]; then
    sudo bootctl set-default "$entry"
  else
    warn "No CachyOS Type #1 entry was found. At the next systemd-boot menu, select CachyOS and press 'd' to save it as default."
  fi
  sudo bootctl update || true
else
  warn "systemd-boot is not installed. This script will not replace your boot loader."
fi

log "Creating a PowerDevil systemd user override"
mkdir -p "$HOME/.config/systemd/user/plasma-powerdevil.service.d"
cat > "$HOME/.config/systemd/user/plasma-powerdevil.service.d/override.conf" <<'EOF'
[Service]
Environment=POWERDEVIL_NO_DDCUTIL=1
EOF
systemctl --user daemon-reload

log "Configuring zram with local administrator policy"
sudo install -d -m 0755 /etc/systemd
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
compression-algorithm = lz4
zram-size = ram
swap-priority = 100
fs-type = swap
EOF
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || warn "zram restart failed; it may require a reboot or zram-generator."

log "Installing an ADIOS rule for non-rotational NVMe drives"
sudo install -d -m 0755 /etc/udev/rules.d
sudo tee /etc/udev/rules.d/60-ioschedulers.rules >/dev/null <<'EOF'
# NVMe: prefer ADIOS when the active kernel exposes it.
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="adios"
EOF
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block || true
if ! grep -qw adios /sys/block/nvme*/queue/scheduler 2>/dev/null; then
  warn "ADIOS is not currently exposed (expected until booting linux-cachyos, or unsupported by this kernel/device)."
fi

if [[ "$SETUP_NAS" == ask ]]; then
  read -r -p "Configure the NAS mount ${NAS_SHARE} at ${NAS_MOUNT}? [y/N] " answer
  [[ ${answer,,} == y || ${answer,,} == yes ]] && SETUP_NAS=yes || SETUP_NAS=no
fi
if [[ "$SETUP_NAS" == yes ]]; then
  log "Configuring the NAS mount"
  read -r -p "NAS username: " nas_user
  read -r -s -p "NAS password: " nas_pass; printf '\n'
  read -r -p "NAS domain (blank if none): " nas_domain
  sudo install -d -m 0700 -o root -g root /etc/samba/credentials
  { printf 'username=%s\npassword=%s\n' "$nas_user" "$nas_pass"; [[ -n "$nas_domain" ]] && printf 'domain=%s\n' "$nas_domain"; } \
    | sudo tee /etc/samba/credentials/share >/dev/null
  sudo chmod 600 /etc/samba/credentials/share
  sudo chown root:root /etc/samba/credentials/share
  sudo install -d -m 0755 "$NAS_MOUNT"
  fstab_line="$NAS_SHARE $NAS_MOUNT cifs _netdev,nofail,vers=3.1.1,credentials=/etc/samba/credentials/share,uid=$NAS_UID,gid=$NAS_GID,x-systemd.automount 0 0"
  sudo sed -i '\|credentials=/etc/samba/credentials/share|d' /etc/fstab
  printf '%s\n' "$fstab_line" | sudo tee -a /etc/fstab >/dev/null
  sudo systemctl daemon-reload
  sudo mount -a || warn "NAS mount test failed; check address, credentials, SMB version, and network access."
fi

set_ini_key() {
  local file=$1 key=$2 value=$3
  if sudo grep -Eq "^[#[:space:]]*${key}=" "$file"; then
    sudo sed -Ei "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" | sudo tee -a "$file" >/dev/null
  fi
}
log "Reducing systemd stop/abort timeouts"
set_ini_key /etc/systemd/system.conf DefaultTimeoutStopSec 3s
set_ini_key /etc/systemd/user.conf DefaultTimeoutStopSec 5s
set_ini_key /etc/systemd/user.conf DefaultTimeoutAbortSec 5s
sudo systemctl daemon-reexec
systemctl --user daemon-reexec || true

log "Removing unwanted packages when installed"
remove=()
for pkg in plymouth cachyos-plymouth-theme vlc phonon-qt6-vlc; do
  pacman -Q "$pkg" >/dev/null 2>&1 && remove+=("$pkg")
done
((${#remove[@]})) && sudo pacman -Rns --noconfirm -- "${remove[@]}" || true

log "Configuring fish without modifying CachyOS vendor files"
fish_path="$(command -v fish)"
grep -qxF "$fish_path" /etc/shells || printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null
chsh -s "$fish_path"
mkdir -p "$HOME/.config/fish/conf.d"
cat > "$HOME/.config/fish/conf.d/99-local.fish" <<'EOF'
# Personal configuration. Keeping this in ~/.config avoids package-upgrade conflicts.
alias ll='ls -lah'
alias update='sudo pacman -Syu'
alias cleanup='sudo pacman -Rns (pacman -Qtdq)'
EOF
# CachyOS fish config commonly launches fastfetch from this user file. Comment only that call, if present.
if [[ -f "$HOME/.config/fish/config.fish" ]]; then
  sed -Ei 's/^([[:space:]]*)(fastfetch)([[:space:]]*)$/\1# \2 disabled by arch-cachy-setup\3/' "$HOME/.config/fish/config.fish"
fi

log "Setup complete"
printf '%s\n' \
  "Reboot, then verify: uname -r; swapon --show; bootctl status" \
  "Run fish_config later from a terminal if you want its browser-based configuration UI." 
