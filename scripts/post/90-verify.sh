#!/usr/bin/env bash
set -euo pipefail

STEP="90-verify"
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

echo "== ${STEP} =="
date -Is
echo "VERIFY_ENFORCE=${VERIFY_ENFORCE:-false}"
echo "KERNEL_MODE=${KERNEL_MODE:-latest}"

# Helpers
fail=0
warn_or_fail() {
  local msg="$1"
  if [[ "${VERIFY_ENFORCE:-false}" == "true" ]]; then
    echo "ERROR: ${msg}"
    fail=1
  else
    echo "WARN: ${msg}"
  fi
}

# Kernel
RUNNING_KERNEL="$(uname -r || true)"
echo ""
echo "[Kernel running]"
echo "uname -r: ${RUNNING_KERNEL}"

echo ""
echo "[Kernel packages installed]"
rpm -q kernel kernel-core kernel-modules kernel-modules-extra || true

# KDE/Qt versions (kinfo best-effort)
echo ""
echo "[KDE / Qt via kinfo (if available)]"
if command -v kinfo >/dev/null 2>&1; then
  kinfo || true
  PLASMA="$(kinfo | awk -F': ' '/KDE Plasma Version/ {print $2}' | head -n1 || true)"
  KF6="$(kinfo | awk -F': ' '/KDE Frameworks Version/ {print $2}' | head -n1 || true)"
  QT="$(kinfo | awk -F': ' '/Qt Version/ {print $2}' | head -n1 || true)"
else
  echo "kinfo unavailable; using rpm queries"
  PLASMA=""
  KF6=""
  QT=""
fi

echo ""
echo "[RPM version spot checks]"
rpm -q plasma-desktop || true
rpm -q kf6-kcoreaddons || true
rpm -q qt6-qtbase || true

# Expectations (optional)
echo ""
echo "[Expectations]"
echo "EXPECTED_PLASMA=${EXPECTED_PLASMA:-}"
echo "EXPECTED_KF6=${EXPECTED_KF6:-}"
echo "EXPECTED_QT=${EXPECTED_QT:-}"
echo "EXPECTED_KERNEL_FULL=${EXPECTED_KERNEL_FULL:-}"

if [[ -n "${EXPECTED_PLASMA:-}" && -n "${PLASMA:-}" && "${PLASMA}" != "${EXPECTED_PLASMA}" ]]; then
  warn_or_fail "Plasma mismatch: expected ${EXPECTED_PLASMA}, got ${PLASMA}"
fi
if [[ -n "${EXPECTED_KF6:-}" && -n "${KF6:-}" && "${KF6}" != "${EXPECTED_KF6}" ]]; then
  warn_or_fail "KF6 mismatch: expected ${EXPECTED_KF6}, got ${KF6}"
fi
if [[ -n "${EXPECTED_QT:-}" && -n "${QT:-}" && "${QT}" != "${EXPECTED_QT}" ]]; then
  warn_or_fail "Qt mismatch: expected ${EXPECTED_QT}, got ${QT}"
fi
if [[ -n "${EXPECTED_KERNEL_FULL:-}" && "${RUNNING_KERNEL}" != "${EXPECTED_KERNEL_FULL}" ]]; then
  # In mode latest, mismatch may be normal if kernel moved forward
  warn_or_fail "Kernel mismatch: expected ${EXPECTED_KERNEL_FULL}, running ${RUNNING_KERNEL}"
fi

# Latest kernel available (dynamic mode support)
echo ""
echo "[Latest kernel EVR from enabled repos]"
LATEST_EVR="$(dnf repoquery --arch=x86_64 --latest-limit=1 --qf '%{VERSION}-%{RELEASE}' kernel-core 2>/dev/null | head -n1 || true)"
echo "latest kernel-core EVR: ${LATEST_EVR:-unknown}"

echo ""
echo "[32-bit Vulkan/Mesa libraries]"
rpm -q mesa-vulkan-drivers.i686 vulkan-loader.i686 mesa-dri-drivers.i686 || true

echo ""
echo "[Services]"
systemctl is-enabled tuned 2>/dev/null || true
systemctl is-enabled fstrim.timer 2>/dev/null || true

echo ""
echo "[ZRAM]"
lsblk | grep -i zram || true
swapon --show || true
cat /proc/sys/vm/swappiness 2>/dev/null || true

echo ""
echo "[SDDM Wayland config]"
if [[ -f /etc/sddm.conf.d/10-fedora43-wayland.conf ]]; then
  cat /etc/sddm.conf.d/10-fedora43-wayland.conf
else
  echo "INFO: no explicit SDDM Wayland config file found."
fi

echo ""
echo "[Apps inventory]"
echo "RPM:"
rpm -q steam chromium vlc code gamemode mangohud gamescope vkBasalt 2>/dev/null || true
echo "Flatpak (${FLATPAK_SCOPE:-system}):"
if [[ "${FLATPAK_SCOPE:-system}" == "user" ]]; then
  flatpak list --user --app || true
else
  flatpak list --system --app || true
fi

if [[ "${fail}" -ne 0 ]]; then
  echo "VERIFY FAILED (strict mode)."
  exit 2
fi

touch "${STEP_DIR}/${STEP}.done"
echo "VERIFY OK."
