# Fedora 43 (x86_64) - KDE Plasma (Wayland) - Gaming automation
#
# BOOT PARAMS (required):
#   ks_disk=<disk>          ex: nvme0n1, sda   (SECURITY: required)
#   ks_repo=<owner>/<repo>  ex: myuser/fedora43-gaming
#
# BOOT PARAMS (optional):
#   ks_user=<username>      default: gamer
#   ks_pw_hash='<crypt>'    if absent -> user locked (secure by default)
#
# Notes:
# - Use via boot option: inst.ks=<URL>. See Fedora/Anaconda docs. (not inside code)
# - Netinstall needs network to fetch packages; ks_repo fetched from GitHub in %post.

text
reboot
eula --agreed

lang fr_FR.UTF-8
keyboard --vckeymap=us --xlayouts=us
timezone Europe/Paris --utc

network --bootproto=dhcp --activate --onboot=on

services --enabled="NetworkManager,sshd,firewalld"
firewall --enabled --service=ssh
selinux --enforcing

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-43&arch=x86_64"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f43&arch=x86_64"

# ---------- %pre: require ks_disk and ks_repo ----------
%pre --interpreter=/bin/bash
set -euo pipefail

getarg() {
  local key="$1"
  tr ' ' '\n' < /proc/cmdline | sed -n "s/^${key}=//p" | tail -n1
}

KS_DISK="$(getarg ks_disk || true)"
KS_REPO="$(getarg ks_repo || true)"
KS_USER="$(getarg ks_user || true)"
KS_PW_HASH="$(getarg ks_pw_hash || true)"

if [[ -z "${KS_DISK}" ]]; then
  echo "ERROR: ks_disk= est obligatoire (ex: ks_disk=nvme0n1). Abandon." > /dev/tty
  exit 1
fi

if [[ -z "${KS_REPO}" ]]; then
  echo "ERROR: ks_repo= est obligatoire (format owner/repo). Abandon." > /dev/tty
  exit 1
fi

if ! [[ "${KS_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: ks_repo invalide (format requis: owner/repo). Abandon." > /dev/tty
  exit 1
fi

if [[ -z "${KS_USER}" ]]; then
  KS_USER="gamer"
fi

# Disk layout include
cat > /tmp/disk.ks <<EOF
ignoredisk --only-use=${KS_DISK}
zerombr
clearpart --all --initlabel --drives=${KS_DISK}
# Btrfs par défaut sur Fedora desktop ; autopart est robuste
autopart --type=btrfs
EOF

# User include (secure-by-default if no hash)
if [[ -n "${KS_PW_HASH}" ]]; then
  cat > /tmp/user.ks <<EOF
rootpw --lock
user --name=${KS_USER} --groups=wheel --password="${KS_PW_HASH}" --iscrypted
EOF
else
  cat > /tmp/user.ks <<EOF
rootpw --lock
user --name=${KS_USER} --groups=wheel --lock
EOF
fi
%end

%include /tmp/disk.ks
%include /tmp/user.ks

# ---------- Packages ----------
%packages
@core
@standard
@kde-desktop-environment

# Provisioning basics
bash
sudo
curl
wget
tar
gzip
xz
jq
git

# DNF tools (repoquery, config-manager, etc.)
dnf-plugins-core

# Flatpak support
flatpak

# Wayland greeter configuration for SDDM (Fedora package)
sddm-wayland-plasma

# Vulkan + Mesa (including 32-bit) for Steam/Proton
mesa-dri-drivers
mesa-dri-drivers.i686
mesa-vulkan-drivers
mesa-vulkan-drivers.i686
vulkan-loader
vulkan-loader.i686
vulkan-tools

# Gaming tools (best-effort; some may be pulled later too)
gamemode
mangohud
gamescope
vkBasalt

# System tuning building blocks
tuned
zram-generator
zram-generator-defaults

# Boot tooling (optional but helpful)
grubby
%end

# ---------- %post: clone GitHub repo + install service ----------
%post --interpreter=/bin/bash --log=/root/ks-post.log
set -euo pipefail

getarg() {
  local key="$1"
  tr ' ' '\n' < /proc/cmdline | sed -n "s/^${key}=//p" | tail -n1
}

KS_DISK="$(getarg ks_disk || true)"
KS_REPO="$(getarg ks_repo || true)"
KS_USER="$(getarg ks_user || true)"

mkdir -p /etc/fedora43-gaming

cat > /etc/fedora43-gaming/installer.env <<EOF
KS_DISK="${KS_DISK}"
KS_REPO="${KS_REPO}"
KS_USER="${KS_USER}"
EOF

# Deploy repo
install -d -m 0755 /opt/fedora43-gaming
cd /opt/fedora43-gaming

curl -fsSL -L "https://github.com/${KS_REPO}/archive/refs/heads/main.tar.gz" -o /tmp/fedora43-gaming.tar.gz
tar -xzf /tmp/fedora43-gaming.tar.gz --strip-components=1 -C /opt/fedora43-gaming
rm -f /tmp/fedora43-gaming.tar.gz

# Ensure config exists on target system
install -d -m 0755 /etc/fedora43-gaming
if [[ ! -f /etc/fedora43-gaming/fedora43-gaming.conf ]]; then
  install -m 0644 /opt/fedora43-gaming/config/fedora43-gaming.conf /etc/fedora43-gaming/fedora43-gaming.conf
fi

# Install systemd unit
install -m 0644 /opt/fedora43-gaming/systemd/fedora43-gaming-firstboot.service \
  /etc/systemd/system/fedora43-gaming-firstboot.service

# Enable service without requiring systemctl runtime
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/fedora43-gaming-firstboot.service \
  /etc/systemd/system/multi-user.target.wants/fedora43-gaming-firstboot.service

# Permissions
chmod +x /opt/fedora43-gaming/scripts/firstboot/firstboot.sh
chmod +x /opt/fedora43-gaming/scripts/post/*.sh
%end
