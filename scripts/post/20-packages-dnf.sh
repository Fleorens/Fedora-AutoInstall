#!/usr/bin/env bash
set -euo pipefail

STEP="20-packages-dnf"
INSTALLER_ENV="/etc/fedora43-gaming/installer.env"
CONF="/etc/fedora43-gaming/fedora43-gaming.conf"

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

# System upgrade (best-effort)
dnf -y upgrade --refresh || true

# Helper: install packages but don't fail whole step if one is missing
dnf_install_best_effort() {
  local pkgs=("$@")
  if ! dnf -y install "${pkgs[@]}"; then
    echo "WARN: some packages failed to install: ${pkgs[*]}"
    return 0
  fi
}

# Gaming stack + 32-bit libs
dnf_install_best_effort \
  steam steam-devices \
  gamemode mangohud gamescope vkBasalt \
  mesa-dri-drivers mesa-vulkan-drivers vulkan-loader vulkan-tools \
  mesa-dri-drivers.i686 mesa-vulkan-drivers.i686 vulkan-loader.i686

# Apps RPM requested
dnf_install_best_effort \
  chromium \
  vlc \
  code

# Useful extras
dnf_install_best_effort \
  nmap \
  curl wget git jq \
  tuned zram-generator zram-generator-defaults

touch "${STEP_DIR}/${STEP}.done"
echo "DONE."
