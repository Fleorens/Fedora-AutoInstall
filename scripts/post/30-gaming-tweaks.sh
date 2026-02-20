#!/usr/bin/env bash
set -euo pipefail

STEP="30-gaming-tweaks"
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

# tuned
dnf -y install tuned tuned-ppd || true
systemctl enable --now tuned || true
if [[ -n "${TUNED_PROFILE:-}" ]]; then
  tuned-adm profile "${TUNED_PROFILE}" || true
fi

# fstrim.timer
if [[ "${ENABLE_FSTRIM_TIMER:-true}" == "true" ]]; then
  systemctl enable --now fstrim.timer || true
fi

# zram + swappiness
if [[ "${ENABLE_ZRAM_TWEAKS:-true}" == "true" ]]; then
  dnf -y install zram-generator zram-generator-defaults || true

  mkdir -p /etc/systemd/zram-generator.conf.d
  cat > /etc/systemd/zram-generator.conf.d/99-fedora43-gaming.conf <<EOF
[zram0]
zram-size = ${ZRAM_SIZE_EXPR:-ram / 4}
compression-algorithm = zstd
EOF

  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-fedora43-gaming.conf <<EOF
vm.swappiness = ${VM_SWAPPINESS:-10}
EOF

  sysctl --system || true
  systemctl restart systemd-zram-setup@zram0.service || true
fi

# SDDM Wayland enforcement
if [[ "${ENABLE_SDDM_WAYLAND:-true}" == "true" ]]; then
  dnf -y install sddm sddm-wayland-plasma || true
  mkdir -p /etc/sddm.conf.d
  cat > /etc/sddm.conf.d/10-fedora43-wayland.conf <<'EOF'
[General]
DisplayServer=wayland
EOF
  systemctl enable --now sddm || true
  systemctl set-default graphical.target || true
fi

# Optional kernel cmdline tweaks (OFF by default)
if [[ "${ENABLE_KERNEL_CMDLINE_TWEAKS:-false}" == "true" && -n "${KERNEL_CMDLINE_ARGS:-}" ]]; then
  echo "INFO: applying kernel cmdline args via grubby: ${KERNEL_CMDLINE_ARGS}"
  for arg in ${KERNEL_CMDLINE_ARGS}; do
    grubby --update-kernel=ALL --args="${arg}" || true
  done
fi

# ---------- Kernel install logic ----------
# Helpers to toggle updates-testing (Fedora QA docs recommend these setopt patterns)
enable_updates_testing() {
  dnf config-manager setopt updates-testing.enabled=true || true
  dnf -y makecache || true
}
disable_updates_testing() {
  dnf config-manager setopt updates-testing.enabled=false || true
  dnf -y makecache || true
}

kernel_evr_latest() {
  # primary: repoquery latest-limit
  local evr
  evr="$(dnf repoquery --arch=x86_64 --latest-limit=1 --qf '%{VERSION}-%{RELEASE}' kernel-core 2>/dev/null | head -n1 || true)"
  if [[ -n "${evr}" ]]; then
    echo "${evr}"
    return 0
  fi
  # fallback: list showduplicates parse last line
  evr="$(dnf list --showduplicates kernel-core.x86_64 2>/dev/null | awk '/kernel-core\.x86_64/ {print $2}' | tail -n1 || true)"
  echo "${evr}"
}

kernel_install_evr() {
  local evr="$1"
  local full="${evr}.x86_64"
  echo "INFO: installing kernel EVR=${evr}"
  dnf -y install \
    "kernel-${full}" \
    "kernel-core-${full}" \
    "kernel-modules-${full}" \
    "kernel-modules-extra-${full}" || return 1

  # best-effort: set default kernel
  if [[ -e "/boot/vmlinuz-${full}" ]]; then
    grubby --set-default "/boot/vmlinuz-${full}" || true
  fi
}

kernel_versionlock_add() {
  local evr="$1"
  echo "INFO: enabling kernel versionlock for ${evr}"
  if ! dnf versionlock add "kernel-${evr}.*" "kernel-core-${evr}.*" "kernel-modules-${evr}.*" "kernel-modules-extra-${evr}.*" 2>/dev/null; then
    dnf -y install dnf-plugins-core || true
    dnf versionlock add "kernel-${evr}.*" "kernel-core-${evr}.*" "kernel-modules-${evr}.*" "kernel-modules-extra-${evr}.*" || true
  fi
}

KMODE="${KERNEL_MODE:-latest}"
KCHAN="${KERNEL_CHANNEL:-stable}"

if [[ "${KMODE}" == "latest" ]]; then
  echo "INFO: KERNEL_MODE=latest (channel=${KCHAN})"
  if [[ "${KCHAN}" == "testing" ]]; then
    enable_updates_testing
  else
    disable_updates_testing
  fi

  LATEST_EVR="$(kernel_evr_latest)"
  if [[ -z "${LATEST_EVR}" ]]; then
    echo "WARN: cannot determine latest kernel EVR from repos (skip)"
  else
    kernel_install_evr "${LATEST_EVR}" || echo "WARN: latest kernel install failed"
  fi

elif [[ "${KMODE}" == "pin" ]]; then
  echo "INFO: KERNEL_MODE=pin TARGET_KERNEL_NVR=${TARGET_KERNEL_NVR:-}"
  EVR="${TARGET_KERNEL_NVR:-}"
  if [[ -z "${EVR}" ]]; then
    echo "WARN: TARGET_KERNEL_NVR empty (skip)"
  else
    if rpm -q "kernel-core-${EVR}.x86_64" >/dev/null 2>&1; then
      echo "INFO: pinned kernel already installed"
    else
      if ! kernel_install_evr "${EVR}"; then
        echo "WARN: pinned kernel not installable from current repos"
        if [[ "${ALLOW_UPDATES_TESTING:-true}" == "true" ]]; then
          echo "INFO: enabling updates-testing temporarily to fetch pinned kernel"
          enable_updates_testing
          kernel_install_evr "${EVR}" || echo "WARN: still failed to install pinned kernel"
          disable_updates_testing
        fi
      fi
    fi

    if [[ "${KERNEL_VERSIONLOCK:-false}" == "true" ]]; then
      kernel_versionlock_add "${EVR}"
    fi
  fi
else
  echo "WARN: Unknown KERNEL_MODE=${KMODE} (skip)"
fi

touch "${STEP_DIR}/${STEP}.done"
echo "DONE."
