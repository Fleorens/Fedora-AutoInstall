#!/usr/bin/env bash
# tools/build-ks-iso.sh
#
# Build a custom Fedora installer ISO embedding a Kickstart using mkksiso (lorax).
#
# Usage:
#   ./tools/build-ks-iso.sh -i <input.iso> -k <kickstart.ks> -o <output.iso> \
#       [--add <path>]... [--cmdline "<args>"] [--rm-args "<args>"] [--volid "NAME"] \
#       [--skip-mkefiboot] [--no-md5sum] [--log <logfile>]
#
# Notes:
# - mkksiso needs host architecture to match ISO architecture (checked by mkksiso via .discinfo).
# - Since lorax/mkksiso 38.4, root is recommended to rebuild EFI boot image; otherwise use --skip-mkefiboot.

set -euo pipefail

LOGFILE="./build-ks-iso.log"
ISO_IN="/home/florian/Documents/scripts/Fedora-Everything-netinst-x86_64-43-1.6.iso"
KS_FILE="/home/florian/Documents/scripts/fedora43-custom-flo/kickstart/fedora43-kde-gaming.ks"
ISO_OUT="/home/florian/Documents/scripts/Fedora-Everything-FLO.iso"
declare -a ADD_PATHS=()
CMDLINE=''
RM_ARGS=""
VOLID=""
SKIP_MKEFIBOOT="false"
NO_MD5SUM="false"

usage() {
  cat <<EOF
Usage: $0 -i <input.iso> -k <kickstart.ks> -o <output.iso> [options]

Required:
  -i, --input       Path to input Fedora installer ISO (netinst/boot ISO)
  -k, --kickstart   Path to Kickstart file (.ks or ks.cfg)
  -o, --output      Path to output ISO to create

Options:
  --add <path>         Add file or directory to ISO (repeatable)
  --cmdline "<args>"   Add kernel cmdline arguments to ISO entries
  --rm-args "<args>"   Remove kernel cmdline arguments from ISO entries
  --volid "NAME"       Set ISO volume ID
  --skip-mkefiboot      Allow running without root (UEFI boot from USB may be impacted)
  --no-md5sum           Do not run implantisomd5 on output ISO
  --log <file>          Log file path (default: ./build-ks-iso.log)

Examples:
  sudo $0 -i Fedora-Everything-netinst-x86_64-43.iso \\
       -k kickstart/fedora43-gaming-kde.ks \\
       -o Fedora43-Netinst-KS.iso

  sudo $0 -i Fedora-Everything-netinst-x86_64-43.iso \\
       -k kickstart/fedora43-gaming-kde.ks \\
       -o Fedora43-Netinst-KS+payload.iso \\
       --add payload/ --cmdline "inst.text"
EOF
}

die() { echo "ERROR: $*" >&2; exit 2; }

log_init() {
  if [[ -z "${LOGFILE}" ]]; then
    LOGFILE="./build-ks-iso.log"
  fi
  mkdir -p "$(dirname "${LOGFILE}")" 2>/dev/null || true
  exec > >(tee -a "${LOGFILE}") 2>&1
}

need_cmd() {
  local c="$1"
  command -v "${c}" >/dev/null 2>&1 || die "Command not found: ${c}. Install prerequisites (e.g., lorax provides mkksiso)."
}

run_as_root() {
  # If already root, run directly. Otherwise try sudo.
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo "$@"
    else
      die "Not root and sudo not found. Re-run as root or install sudo."
    fi
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--input) ISO_IN="${2:-}"; shift 2;;
      -k|--kickstart) KS_FILE="${2:-}"; shift 2;;
      -o|--output) ISO_OUT="${2:-}"; shift 2;;
      --add) ADD_PATHS+=("${2:-}"); shift 2;;
      --cmdline) CMDLINE="${2:-}"; shift 2;;
      --rm-args) RM_ARGS="${2:-}"; shift 2;;
      --volid) VOLID="${2:-}"; shift 2;;
      --skip-mkefiboot) SKIP_MKEFIBOOT="true"; shift 1;;
      --no-md5sum) NO_MD5SUM="true"; shift 1;;
      --log) LOGFILE="${2:-}"; shift 2;;
      -h|--help) usage; exit 0;;
      *) die "Unknown argument: $1 (use --help)";;
    esac
  done
}

main() {
  parse_args "$@"
  log_init

  echo "== build-ks-iso =="
  date -Is
  echo "Host arch: $(uname -m)"
  echo "mkksiso: $(command -v mkksiso || echo 'not found')"

  [[ -n "${ISO_IN}" ]] || die "Missing --input"
  [[ -n "${KS_FILE}" ]] || die "Missing --kickstart"
  [[ -n "${ISO_OUT}" ]] || die "Missing --output"

  [[ -f "${ISO_IN}" ]] || die "Input ISO not found: ${ISO_IN}"
  [[ -f "${KS_FILE}" ]] || die "Kickstart file not found: ${KS_FILE}"

  # Ensure mkksiso exists (lorax)
  need_cmd mkksiso

  # Validate add paths
  for p in "${ADD_PATHS[@]}"; do
    [[ -e "${p}" ]] || die "--add path not found: ${p}"
  done

  # Prepare mkksiso args
  declare -a MKARGS=()
  MKARGS+=( "--ks" "${KS_FILE}" )

  for p in "${ADD_PATHS[@]}"; do
    MKARGS+=( "--add" "${p}" )
  done

  if [[ -n "${CMDLINE}" ]]; then
    MKARGS+=( "--cmdline" "${CMDLINE}" )
  fi

  if [[ -n "${RM_ARGS}" ]]; then
    MKARGS+=( "--rm-args" "${RM_ARGS}" )
  fi

  if [[ -n "${VOLID}" ]]; then
    MKARGS+=( "-V" "${VOLID}" )
  fi

  if [[ "${NO_MD5SUM}" == "true" ]]; then
    MKARGS+=( "--no-md5sum" )
  fi

  # Root vs --skip-mkefiboot
  if [[ "${EUID}" -ne 0 && "${SKIP_MKEFIBOOT}" != "true" ]]; then
    echo "INFO: Not running as root. Enabling --skip-mkefiboot automatically."
    echo "WARN: ISO may not be fully UEFI-bootable from USB in some scenarios."
    MKARGS+=( "--skip-mkefiboot" )
  elif [[ "${SKIP_MKEFIBOOT}" == "true" ]]; then
    MKARGS+=( "--skip-mkefiboot" )
  fi

  echo ""
  echo "Input ISO : ${ISO_IN}"
  echo "Kickstart : ${KS_FILE}"
  echo "Output ISO: ${ISO_OUT}"
  echo "mkksiso args: ${MKARGS[*]}"

  # Build
  run_as_root mkksiso "${MKARGS[@]}" "${ISO_IN}" "${ISO_OUT}"

  echo ""
  echo "Build done: ${ISO_OUT}"

  # Post: SHA256 checksum file
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${ISO_OUT}" | tee "${ISO_OUT}.sha256"
    echo "SHA256 written to: ${ISO_OUT}.sha256"
  else
    echo "WARN: sha256sum missing; checksum not generated."
  fi
}

main "$@"
