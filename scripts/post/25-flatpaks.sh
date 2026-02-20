#!/usr/bin/env bash
set -euo pipefail

STEP="25-flatpaks"
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

SCOPE="${FLATPAK_SCOPE:-system}"
FP_SCOPE_FLAG="--system"
if [[ "${SCOPE}" == "user" ]]; then
  FP_SCOPE_FLAG="--user"
fi

echo "== ${STEP} (${SCOPE}) =="
date -Is

dnf -y install flatpak curl jq || true

# Ensure Flathub
flatpak remote-add ${FP_SCOPE_FLAG} --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

install_flatpak() {
  local appid="$1"
  if flatpak list ${FP_SCOPE_FLAG} --app --columns=application | awk '{print $1}' | grep -qx "${appid}"; then
    echo "INFO: already installed: ${appid}"
    return 0
  fi
  echo "INFO: installing: ${appid}"
  flatpak install ${FP_SCOPE_FLAG} -y flathub "${appid}" || {
    echo "WARN: could not install ${appid} (skip)"
    return 0
  }
}

# Required Flatpaks
install_flatpak "tv.plex.PlexDesktop"
install_flatpak "io.github.shiftey.Desktop"
install_flatpak "com.heroicgameslauncher.hgl"
install_flatpak "net.davidotek.pupgui2"
install_flatpak "org.freecad.FreeCAD"
install_flatpak "com.discordapp.Discord"
install_flatpak "org.nmap.Zenmap"
install_flatpak "org.angryip.ipscan"

# Creality Print: best-effort from GitHub Releases if a .flatpak exists
CREALITY_REPO="CrealityOfficial/CrealityPrint"
API="https://api.github.com/repos/${CREALITY_REPO}/releases/latest"

echo "INFO: Creality Print best-effort (GitHub Releases .flatpak)"
TMPD="$(mktemp -d)"
trap 'rm -rf "${TMPD}"' EXIT

REL_JSON="$(curl -fsSL "${API}" 2>/dev/null || true)"
if [[ -z "${REL_JSON}" ]]; then
  echo "WARN: cannot fetch Creality release metadata (skip)"
else
  ASSET_URL="$(echo "${REL_JSON}" | jq -r '.assets[] | select(.name|test("\\.flatpak$";"i")) | .browser_download_url' | head -n1 || true)"
  ASSET_NAME="$(echo "${REL_JSON}" | jq -r '.assets[] | select(.name|test("\\.flatpak$";"i")) | .name' | head -n1 || true)"
  if [[ -z "${ASSET_URL}" || "${ASSET_URL}" == "null" ]]; then
    echo "WARN: no .flatpak asset found for Creality Print (skip)"
  else
    echo "INFO: downloading ${ASSET_NAME}"
    curl -fL "${ASSET_URL}" -o "${TMPD}/${ASSET_NAME}" || true
    if [[ -s "${TMPD}/${ASSET_NAME}" ]]; then
      echo "INFO: installing local Creality flatpak bundle"
      flatpak install ${FP_SCOPE_FLAG} -y "${TMPD}/${ASSET_NAME}" || echo "WARN: install failed (runtime missing/EoL). Continuing."
    fi
  fi
fi

flatpak update ${FP_SCOPE_FLAG} -y || true

touch "${STEP_DIR}/${STEP}.done"
echo "DONE."
