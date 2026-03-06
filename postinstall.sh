#!/bin/bash
# "Things To Do!" script for a fresh Fedora (netinstall -> KDE + apps + gaming)
# Modular version with interactive module selection

set -euo pipefail

# ============================================================================
# CONFIGURATION - Modify these to your liking
# ============================================================================
HOSTNAME="fedora-kde-host"

# ============================================================================
# INTERNAL VARIABLES
# ============================================================================
if [ "${EUID}" -ne 0 ]; then
    echo "Please run this script with sudo"
    exit 1
fi

ACTUAL_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "${ACTUAL_USER}" || "${ACTUAL_USER}" == "root" ]]; then
    echo "ERROR: run this via sudo from a normal user."
    echo "Example: curl -fsSLO <raw_url>; chmod +x postinstall.sh; sudo ./postinstall.sh"
    exit 1
fi

ACTUAL_HOME="$(getent passwd "$ACTUAL_USER" | cut -d: -f6)"
LOG_FILE="/var/log/fedora_things_to_do.log"

# ============================================================================
# HELPERS
# ============================================================================
color_echo() {
    local color="$1" text="$2"
    case "$color" in
        red)     echo -e "\033[0;31m$text\033[0m" ;;
        green)   echo -e "\033[0;32m$text\033[0m" ;;
        yellow)  echo -e "\033[1;33m$text\033[0m" ;;
        blue)    echo -e "\033[0;34m$text\033[0m" ;;
        cyan)    echo -e "\033[0;36m$text\033[0m" ;;
        *)       echo "$text" ;;
    esac
}

log_message() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | tee -a "$LOG_FILE"
}

section_header() {
    echo ""
    color_echo "cyan" "========================================"
    color_echo "cyan" "  $1"
    color_echo "cyan" "========================================"
    log_message "START: $1"
}

section_done() {
    log_message "DONE: $1"
    color_echo "green" "  -> $1 done."
}

# Ask the user a yes/no question. Returns 0 for yes, 1 for no.
ask_yes_no() {
    local prompt="$1"
    local choice
    while true; do
        read -rp "$(color_echo yellow "$prompt (y/n): ")" choice
        case "$choice" in
            [yY]) return 0 ;;
            [nN]) return 1 ;;
            *)    echo "Please answer y or n." ;;
        esac
    done
}

# Trap for clean error reporting
trap 'log_message "ERROR: script failed at line $LINENO (exit code $?)"; color_echo red "Script failed at line $LINENO. Check $LOG_FILE for details."' ERR

# ============================================================================
# MODULES
# ============================================================================

# --- Module: System base (always runs) --------------------------------------
mod_system_base() {
    section_header "System Base"

    color_echo "yellow" "Ensuring base tools are installed..."
    dnf install -y sudo curl wget git ca-certificates NetworkManager
    systemctl enable --now NetworkManager || true

    color_echo "yellow" "Performing system upgrade..."
    dnf upgrade -y --refresh

    color_echo "yellow" "Setting hostname to '$HOSTNAME'..."
    hostnamectl set-hostname "$HOSTNAME"

    section_done "System base"
}

# --- Module: DNF optimization -----------------------------------------------
mod_dnf_config() {
    section_header "DNF Configuration"

    dnf -y install dnf-plugins-core

    if ! grep -q "^max_parallel_downloads=" /etc/dnf/dnf.conf 2>/dev/null; then
        cp -a /etc/dnf/dnf.conf "/etc/dnf/dnf.conf.bak.$(date +%Y%m%d-%H%M%S)"
        cat >> /etc/dnf/dnf.conf <<'EOF'

# --- tuned by postinstall.sh ---
fastestmirror=True
max_parallel_downloads=10
keepcache=True
EOF
    fi

    color_echo "yellow" "Configuring DNF automatic updates (download only)..."
    dnf install -y dnf-automatic
    cp -a /etc/dnf/automatic.conf "/etc/dnf/automatic.conf.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

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
    section_done "DNF configuration"
}

# --- Module: RPM Fusion + Multimedia codecs ----------------------------------
mod_multimedia() {
    section_header "RPM Fusion + Multimedia Codecs"

    color_echo "yellow" "Enabling RPM Fusion repositories..."
    dnf install -y \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
    dnf update -y @core

    color_echo "yellow" "Installing multimedia codecs..."
    dnf -y install rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data || true
    dnf -y swap ffmpeg-free ffmpeg --allowerasing
    dnf -y group install multimedia || true
    dnf -y group upgrade multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    dnf -y group install sound-and-video || true
    dnf -y group upgrade sound-and-video

    color_echo "yellow" "Installing AMD Hardware Accelerated Codecs..."
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || true
    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || true

    section_done "RPM Fusion + Multimedia"
}

# --- Module: KDE Plasma ------------------------------------------------------
mod_kde_plasma() {
    section_header "KDE Plasma Desktop"

    dnf -y groupinstall "KDE Plasma Workspaces" || dnf -y install @kde-desktop-environment
    dnf -y install sddm plasma-workspace-wayland

    systemctl set-default graphical.target
    systemctl enable sddm

    section_done "KDE Plasma"
}

# --- Module: Flatpak + Flathub -----------------------------------------------
mod_flatpak() {
    section_header "Flatpak + Flathub"

    dnf install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak update -y || true

    section_done "Flatpak + Flathub"
}

# --- Module: Firmware updates ------------------------------------------------
mod_firmware() {
    section_header "Firmware Updates"

    dnf install -y fwupd || true
    fwupdmgr refresh --force || true
    fwupdmgr get-updates || true
    fwupdmgr update -y || true

    section_done "Firmware updates"
}

# --- Module: Virtualization --------------------------------------------------
mod_virtualization() {
    section_header "Virtualization"

    dnf install -y @virtualization

    section_done "Virtualization"
}

# --- Module: Gaming stack ----------------------------------------------------
mod_gaming() {
    section_header "Gaming & Performance Stack"

    # GPU/CPU diagnostic tools
    dnf install -y vulkan-tools mesa-demos kernel-tools

    # Gaming tools
    dnf install -y gamemode mangohud goverlay gamescope vkbasalt tuned

    systemctl enable --now tuned || true
    if tuned-adm list | grep -q "^-\s*latency-performance"; then
        tuned-adm profile latency-performance || true
    else
        tuned-adm profile throughput-performance || true
    fi

    # GameMode user service
    sudo -u "$ACTUAL_USER" env HOME="$ACTUAL_HOME" bash -lc \
        'systemctl --user enable --now gamemoded.service || true'

    section_done "Gaming base"

    # Sub-choices within gaming
    if ask_yes_no "Install Steam?"; then
        dnf install -y steam
        section_done "Steam"
    fi

    if ask_yes_no "Install Heroic Games Launcher? (Flatpak)"; then
        flatpak install -y flathub com.heroicgameslauncher.hgl
        section_done "Heroic Games Launcher"
    fi

    if ask_yes_no "Install ProtonUp-Qt? (Flatpak)"; then
        flatpak install -y flathub net.davidotek.pupgui2
        section_done "ProtonUp-Qt"
    fi
}

# --- Module: Dev tools -------------------------------------------------------
mod_dev_tools() {
    section_header "Developer Tools"

    dnf install -y htop unzip git wget curl
    section_done "CLI essentials"

    if ask_yes_no "Install Visual Studio Code?"; then
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
        section_done "VS Code"
    fi

    if ask_yes_no "Install GitHub Desktop? (Flatpak)"; then
        flatpak install -y flathub io.github.shiftey.Desktop
        section_done "GitHub Desktop"
    fi
}

# --- Module: Applications ----------------------------------------------------
mod_applications() {
    section_header "Applications"

    local apps=(
        "Chromium|dnf|chromium"
        "Thunderbird|dnf|thunderbird"
        "Discord|dnf|discord"
        "VLC|dnf|vlc"
        "LibreOffice|flatpak|org.libreoffice.LibreOffice"
        "RustDesk|flatpak|com.rustdesk.RustDesk"
    )

    for entry in "${apps[@]}"; do
        IFS='|' read -r name method package <<< "$entry"
        if ask_yes_no "Install $name?"; then
            case "$method" in
                dnf)
                    dnf install -y "$package"
                    ;;
                flatpak)
                    flatpak install -y flathub "$package"
                    ;;
            esac
            section_done "$name"
        fi
    done

    # LibreOffice locale fix if it was installed
    if flatpak list | grep -q org.libreoffice.LibreOffice; then
        flatpak install -y --reinstall org.freedesktop.Platform.Locale/x86_64/24.08 || true
        flatpak install -y --reinstall org.libreoffice.LibreOffice.Locale || true
    fi
}

# ============================================================================
# MODULE MENU
# ============================================================================
declare -A MODULES_SELECTED

show_menu() {
    echo ""
    color_echo "cyan" "============================================"
    color_echo "cyan" "   Fedora Post-Install - Module Selection"
    color_echo "cyan" "============================================"
    echo ""
    color_echo "blue" "The following modules will ALWAYS run:"
    echo "  - System base (upgrade, hostname, base tools)"
    echo "  - DNF configuration (parallel downloads, automatic updates)"
    echo ""
    color_echo "blue" "Select optional modules to install:"
    echo ""

    local modules=(
        "multimedia:RPM Fusion + Multimedia codecs (ffmpeg, AMD HW accel)"
        "kde:KDE Plasma Desktop + SDDM (Wayland)"
        "flatpak:Flatpak + Flathub repository"
        "firmware:Firmware updates (fwupd)"
        "virtualization:Virtualization tools (libvirt, qemu)"
        "gaming:Gaming stack (Steam, Heroic, MangoHud, GameMode...)"
        "dev:Developer tools (VS Code, GitHub Desktop, git, htop...)"
        "apps:Applications (Chromium, Thunderbird, Discord, VLC...)"
    )

    for entry in "${modules[@]}"; do
        IFS=':' read -r key desc <<< "$entry"
        if ask_yes_no "  [$key] $desc"; then
            MODULES_SELECTED["$key"]=1
        else
            MODULES_SELECTED["$key"]=0
        fi
    done

    # Summary
    echo ""
    color_echo "cyan" "========== Summary =========="
    color_echo "green" "  [always] System base"
    color_echo "green" "  [always] DNF configuration"
    for entry in "${modules[@]}"; do
        IFS=':' read -r key desc <<< "$entry"
        if [[ "${MODULES_SELECTED[$key]}" == "1" ]]; then
            color_echo "green" "  [yes] $desc"
        else
            color_echo "red"   "  [no]  $desc"
        fi
    done
    echo ""

    if ! ask_yes_no "Proceed with this configuration?"; then
        color_echo "red" "Aborted by user."
        exit 0
    fi
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo ""
    echo "Don't run this script if you didn't build it yourself or don't know what it does."
    echo ""
    read -rp "Press Enter to continue or CTRL+C to cancel..."

    log_message "=== Fedora Post-Install started ==="

    show_menu

    # --- Mandatory modules ---
    mod_system_base
    mod_dnf_config

    # --- Optional modules (in logical order) ---
    [[ "${MODULES_SELECTED[multimedia]}" == "1" ]] && mod_multimedia
    [[ "${MODULES_SELECTED[flatpak]}" == "1" ]]    && mod_flatpak
    [[ "${MODULES_SELECTED[kde]}" == "1" ]]        && mod_kde_plasma
    [[ "${MODULES_SELECTED[firmware]}" == "1" ]]   && mod_firmware
    [[ "${MODULES_SELECTED[virtualization]}" == "1" ]] && mod_virtualization
    [[ "${MODULES_SELECTED[gaming]}" == "1" ]]     && mod_gaming
    [[ "${MODULES_SELECTED[dev]}" == "1" ]]        && mod_dev_tools
    [[ "${MODULES_SELECTED[apps]}" == "1" ]]       && mod_applications

    log_message "=== Fedora Post-Install completed ==="

    echo ""
    echo "Created with <3 for Open Source"
    echo ""
    echo "============================================="
    color_echo "green" "   All selected modules completed!"
    echo "============================================="
    echo ""

    if ask_yes_no "Reboot now?"; then
        color_echo "green" "Rebooting..."
        reboot
    else
        color_echo "yellow" "Reboot skipped. Remember to reboot before using the desktop."
    fi
}

main "$@"
