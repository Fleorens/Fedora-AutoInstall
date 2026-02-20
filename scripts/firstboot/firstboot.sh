#!/usr/bin/env bash
set -euo pipefail

INSTALLER_ENV="/etc/fedora43-gaming/installer.env"
CONF="/etc/fedora43-gaming/fedora43-gaming.conf"

# Safety: refuse without installer.env
if [[ ! -r "${INSTALLER_ENV}" ]]; then
  echo "ERROR: ${INSTALLER_ENV} absent. Refus d'exécuter (sécurité)." >&2
  exit 20
fi

# shellcheck disable=SC1090
source "${INSTALLER_ENV}"

# Safety: refuse without ks_disk
if [[ -z "${KS_DISK:-}" ]]; then
  echo "ERROR: KS_DISK vide dans installer.env. Refus." >&2
  exit 21
fi

# Load config (optional but expected)
if [[ -r "${CONF}" ]]; then
  # shellcheck disable=SC1090
  source "${CONF}"
fi

LOG_DIR="${LOG_DIR:-/var/log/fedora43-gaming}"
STATE_DIR="/var/lib/fedora43-gaming"
STEP_DIR="${STATE_DIR}/steps"
MARKER="${STATE_DIR}/firstboot.complete"

mkdir -p "${LOG_DIR}" "${STEP_DIR}" "${STATE_DIR}"
exec > >(tee -a "${LOG_DIR}/firstboot.log") 2>&1

echo "== Fedora43 KDE Gaming firstboot =="
date -Is
echo "KS_DISK=${KS_DISK}"
echo "KS_REPO=${KS_REPO:-}"
echo "LOG_DIR=${LOG_DIR}"

if [[ -f "${MARKER}" && "${FORCE_REAPPLY:-false}" != "true" ]]; then
  echo "INFO: firstboot déjà complété (${MARKER}). Fin."
  exit 0
fi

# Optional: wait network-online (best-effort)
if command -v nm-online >/dev/null 2>&1; then
  nm-online --timeout=120 || true
fi

SCRIPTS=(
  "/opt/fedora43-gaming/scripts/post/10-repos.sh"
  "/opt/fedora43-gaming/scripts/post/20-packages-dnf.sh"
  "/opt/fedora43-gaming/scripts/post/25-flatpaks.sh"
  "/opt/fedora43-gaming/scripts/post/30-gaming-tweaks.sh"
  "/opt/fedora43-gaming/scripts/post/90-verify.sh"
)

for s in "${SCRIPTS[@]}"; do
  echo ""
  echo "--- Running: ${s} ---"
  if [[ ! -x "${s}" ]]; then
    echo "WARN: script absent ou non-exécutable: ${s} (skip)"
    continue
  fi
  "${s}"
done

touch "${MARKER}"
echo "INFO: marker créé: ${MARKER}"

echo "INFO: désactivation du service firstboot"
systemctl disable --now fedora43-gaming-firstboot.service || true

echo "DONE. Un redémarrage est recommandé si un nouveau noyau a été installé."
