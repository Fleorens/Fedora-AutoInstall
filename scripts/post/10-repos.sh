#!/usr/bin/env bash
set -euo pipefail

STEP="10-repos"
INSTALLER_ENV="/etc/fedora43-gaming/installer.env"
CONF="/etc/fedora43-gaming/fedora43-gaming.conf"

# Safety
if [[ ! -r "${INSTALLER_ENV}" ]]; then
  echo "ERROR: missing ${INSTALLER_ENV}" >&2
  exit 20
fi
# shellcheck disable=SC1090
source "${INSTALLER_ENV}"
if [[ -z "${KS_DISK:-}" ]]; then
  echo "ERROR: KS_DISK missing" >&2
  exit 21
fi

# Config
if [[ -r "${CONF}" ]]; then
  # shellcheck disable=SC1090
  source "${CONF}"
fi

LOG_DIR="${LOG_DIR:-/var/log/fedora43-gaming}"
STATE_DIR="/var/lib/fedora43-gaming"
STEP_DIR="${STATE_DIR}/steps"
mkdir -p "${LOG_DIR}" "${STEP_DIR}"
exec > >(tee -a "${LOG_DIR}/${STEP}.log") 2>&1

if [[ -f "${STEP_DIR}/${STEP}.done" && "${FORCE_REAPPLY:-false}" != "true" ]]; then
  echo "INFO: ${STEP} already done."
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: must run as root" >&2
  exit 1
fi

echo "== ${STEP} =="
date -Is

# Ensure dnf tooling
dnf -y install curl ca-certificates dnf-plugins-core flatpak jq || true

# RPM Fusion (official Fedora quick-docs explain process; using CLI install is standard)
FEDVER="$(rpm -E %fedora)"
dnf -y install \
  "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDVER}.noarch.rpm" \
  "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDVER}.noarch.rpm" || true

# Enable rpmfusion-nonfree-steam if present
if dnf repolist all | awk '{print $1}' | grep -qx "rpmfusion-nonfree-steam"; then
  echo "INFO: enabling rpmfusion-nonfree-steam"
  dnf config-manager setopt rpmfusion-nonfree-steam.enabled=true || true
fi

# Flathub remote (system or user)
SCOPE="${FLATPAK_SCOPE:-system}"
FP_SCOPE_FLAG="--system"
if [[ "${SCOPE}" == "user" ]]; then
  FP_SCOPE_FLAG="--user"
fi

echo "INFO: ensure flathub remote (${SCOPE})"
flatpak remote-add ${FP_SCOPE_FLAG} --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# VS Code repo (official Microsoft doc: yum repo for Fedora/RHEL)
rpm --import https://packages.microsoft.com/keys/microsoft.asc || true

cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf -y makecache || true

touch "${STEP_DIR}/${STEP}.done"
echo "DONE."
