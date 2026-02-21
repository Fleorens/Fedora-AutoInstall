#!/bin/bash
# "Things To Do!" script for a fresh Fedora (netinstall → KDE + apps + gaming)

set -euo pipefail

# Check if the script is run with sudo/root
if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script with sudo"
    exit 1
fi

# Function to echo colored text
color_echo() {
    local color="$1"
    local text="$2"
    case "$color" in
        "red")     echo -e "\033[0;31m$text\033[0m" ;;
        "green")   echo -e "\033[0;32m$text\033[0m" ;;
        "yellow")  echo -e "\033[1;33m$text\033[0m" ;;
        "blue")    echo -e "\033[0;34m$text\033[0m" ;;
        *)         echo "$text" ;;
    esac
}

# ---- Variables / sanity
ACTUAL_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "${ACTUAL_USER}" || "${ACTUAL_USER}" == "root" ]]; then
  echo "ERROR: run this via sudo from a normal user (ex: florian)."
  echo "Example: curl -fsSLO <raw_url>; chmod +x postinstall.sh; sudo ./postinstall.sh"
  exit 1
fi

ACTUAL_HOME="$(eval echo "~${ACTUAL_USER}")"
LOG_FILE="/var/log/fedora_things_to_do.log"
INITIAL_DIR="$(pwd)"

get_timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log_message() {
    local message="$1"
    echo "$(get_timestamp) - $message" | tee -a "$LOG_FILE"
}

# Function to prompt for reboot
prompt_reboot() {
    sudo -u "$ACTUAL_USER" bash -c 'read -p "It is time to reboot the machine. Would you like to do it now? (y/n): " choice; [[ $choice == [yY] ]]'
    if [ $? -eq 0 ]; then
        color_echo "green" "Rebooting..."
        reboot
    else
        color_echo "red" "Reboot canceled."
    fi
}

# Function to backup configuration files
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp -a "$file" "${file}.bak.$(date +%Y%m%d-%H%M%S)"
        color_echo "green" "Backed up $file"
    fi
}

echo ""
echo "╔═════════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                             ║"
echo "║   ░█▀▀░█▀▀░█▀▄░█▀█░█▀▄░█▀█░░░█░█░█▀█░█▀▄░█░█░█▀▀░▀█▀░█▀█░▀█▀░▀█▀░█▀█░█▀█░   ║"
echo "║   ░█▀▀░█▀▀░█░█░█░█░█▀▄░█▀█░░░█▄█░█░█░█▀▄░█▀▄░▀▀█░░█░░█▀█░░█░░░█░░█░█░█░█░   ║"
echo "║   ░▀░░░▀▀▀░▀▀░░▀▀▀░▀░▀░▀░▀░░░▀░▀░▀▀▀░▀░▀░▀░▀░▀▀▀░░▀░░▀░▀░░▀░░▀▀▀░▀▀▀░▀░▀░   ║"
echo "║   ░░░░░░░░░░░░▀█▀░█░█░▀█▀░█▀█░█▀▀░█▀▀░░░▀█▀░█▀█░░░█▀▄░█▀█░█░░░░░░░░░░░░░░   ║"
echo "║   ░░░░░░░░░░░░░█░░█▀█░░█░░█░█░█░█░▀▀█░░░░█░░█░█░░░█░█░█░█░▀░░░░░░░░░░░░░░   ║"
echo "║   ░░░░░░░░░░░░░▀░░▀░▀░▀▀▀░▀░▀░▀▀▀░▀▀▀░░░░▀░░▀▀▀░░░▀▀░░▀▀▀░▀░░░░░░░░░░░░░░   ║"
echo "║                                                                             ║"
echo "╚═════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Post-install: Fedora netinstall → KDE + apps + gaming"
echo "ver. 25.08 / 100 Stars Edition"
echo ""
echo "Don't run this script if you didn't build it yourself or don't know what it does."
echo ""
read -p "Press Enter to continue or CTRL+C to cancel..."

# Ensure basic tools exist (netinstall minimal safety)
color_echo "yellow" "Ensuring base tools are installed (netinstall safety)..."
dnf install -y sudo curl wget git ca-certificates NetworkManager
systemctl enable --now NetworkManager || true

# System Upgrade
color_echo "blue" "Performing system upgrade... This may take a while..."
dnf upgrade -y --refresh

# System Configuration
color_echo "yellow" "Setting hostname..."
hostnamectl set-hostname flo-pc

# Optimize DNF package manager
color_echo "yellow" "Configuring DNF Package Manager..."
backup_file "/etc/dnf/dnf.conf"
dnf -y install dnf-plugins-core

# (Optional) small dnf perf defaults (safe)
if ! grep -q "^max_parallel_downloads=" /etc/dnf/dnf.conf 2>/dev/null; then
  cat >> /etc/dnf/dnf.conf <<'EOF'

# --- tuned by postinstall.sh ---
fastestmirror=True
max_parallel_downloads=10
deltarpm=True
keepcache=True
EOF
fi

# Enable and configure automatic system updates (Option A: download only)
color_echo "yellow" "Configuring DNF automatic updates (download only)..."
dnf install -y dnf-automatic
backup_file "/etc/dnf/automatic.conf"

# Ensure keys exist + set download only
if grep -q "^apply_updates" /etc/dnf/automatic.conf; then
  sed -i 's/^apply_updates\s*=.*/apply_updates = no/' /etc/dnf/automatic.conf
else
  echo "apply_updates = no" >> /etc/dnf/automatic.conf
fi

if grep -q "^download_updates" /etc/dnf/automatic.conf; then
  sed -i 's/^download_updates\s*=.*/download_updates = yes/' /etc/dnf/automatic.conf
else
  echo "download_updates = yes" >> /etc/dnf/automatic.conf
fi

systemctl enable --now dnf-automatic.timer

# Flatpak + Flathub (needed for flatpak installs later)
color_echo "yellow" "Configuring Flatpak + Flathub..."
dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update -y || true

# Firmware updates
color_echo "yellow" "Checking for firmware updates..."
dnf install -y fwupd || true
fwupdmgr refresh --force || true
fwupdmgr get-updates || true
fwupdmgr update -y || true

# Enable RPM Fusion
color_echo "yellow" "Enabling RPM Fusion repositories..."
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf update -y @core

# Multimedia codecs
color_echo "yellow" "Installing multimedia codecs..."
dnf -y install rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data || true
dnf -y swap ffmpeg-free ffmpeg --allowerasing
dnf -y group install multimedia || true
dnf -y group upgrade multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf -y group install sound-and-video || true
dnf -y group upgrade sound-and-video

# AMD HW codecs (freeworld) - keep swap (your choice)
color_echo "yellow" "Installing AMD Hardware Accelerated Codecs..."
dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || true
dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || true

# Virtualization tools
color_echo "yellow" "Installing virtualization tools..."
dnf install -y @virtualization

# ------------------------------------------------------------
# KDE Plasma install (netinstall → full desktop)
# ------------------------------------------------------------
color_echo "yellow" "Installing KDE Plasma desktop..."
dnf -y groupinstall "KDE Plasma Workspaces" || dnf -y install @kde-desktop-environment
dnf -y install sddm plasma-workspace-wayland

systemctl set-default graphical.target
systemctl enable sddm

# Tools useful for your AMD + gaming validation
color_echo "yellow" "Installing GPU/CPU diagnostic tools..."
dnf install -y vulkan-tools mesa-demos kernel-tools

# App Installation
color_echo "yellow" "Installing essential applications..."
dnf install -y htop unzip git wget curl
color_echo "green" "Essential applications installed successfully."

color_echo "yellow" "Installing Chromium..."
dnf install -y chromium
color_echo "green" "Chromium installed successfully."

color_echo "yellow" "Installing Thunderbird..."
dnf install -y thunderbird
color_echo "green" "Thunderbird installed successfully."

color_echo "yellow" "Installing Discord..."
dnf install -y discord
color_echo "green" "Discord installed successfully."

color_echo "yellow" "Installing LibreOffice..."
dnf remove -y libreoffice* || true
flatpak install -y flathub org.libreoffice.LibreOffice
flatpak install -y --reinstall org.freedesktop.Platform.Locale/x86_64/24.08 || true
flatpak install -y --reinstall org.libreoffice.LibreOffice.Locale || true
color_echo "green" "LibreOffice installed successfully."

color_echo "yellow" "Installing Visual Studio Code..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
dnf check-update || true
dnf install -y code
color_echo "green" "Visual Studio Code installed successfully."

color_echo "yellow" "Installing GitHub Desktop..."
flatpak install -y flathub io.github.shiftey.Desktop
color_echo "green" "GitHub Desktop installed successfully."

color_echo "yellow" "Installing VLC..."
dnf install -y vlc
color_echo "green" "VLC installed successfully."

color_echo "yellow" "Installing Steam..."
dnf install -y steam
color_echo "green" "Steam installed successfully."

color_echo "yellow" "Installing Heroic Games Launcher..."
flatpak install -y flathub com.heroicgameslauncher.hgl
color_echo "green" "Heroic Games Launcher installed successfully."

# ------------------------------------------------------------
# Gaming / Perf (no power-profiles-daemon)
# ------------------------------------------------------------
color_echo "yellow" "Installing gaming & performance stack..."
dnf install -y \
  gamemode mangohud goverlay gamescope vkbasalt \
  tuned

systemctl enable --now tuned || true
if tuned-adm list | grep -q "^-\s*latency-performance"; then
  tuned-adm profile latency-performance || true
else
  tuned-adm profile throughput-performance || true
fi

# GameMode user service (best-effort, may be skipped if user session isn't ready yet)
sudo -u "$ACTUAL_USER" env HOME="$ACTUAL_HOME" bash -lc 'systemctl --user enable --now gamemoded.service || true'

color_echo "yellow" "Installing ProtonUp-Qt..."
flatpak install -y flathub net.davidotek.pupgui2
color_echo "green" "ProtonUp-Qt installed successfully."

echo "Created with ❤️ for Open Source"

cd /tmp || cd "$ACTUAL_HOME" || cd /

echo ""
echo "╔═════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                         ║"
echo "║   ░█░█░█▀▀░█░░░█▀▀░█▀█░█▄█░█▀▀░░░▀█▀░█▀█░░░█▀▀░█▀▀░█▀▄░█▀█░█▀▄░█▀█░█░   ║"
echo "║   ░█▄█░█▀▀░█░░░█░░░█░█░█░█░█▀▀░░░░█░░█░█░░░█▀▀░█▀▀░█░█░█░█░█▀▄░█▀█░▀░   ║"
echo "║   ░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀▀▀░░░░▀░░▀▀▀░░░▀░░░▀▀▀░▀▀░░▀▀▀░▀░▀░▀░▀░▀░   ║"
echo "║                                                                         ║"
echo "╚═════════════════════════════════════════════════════════════════════════╝"
echo ""
color_echo "green" "All steps completed. Enjoy!"

prompt_reboot