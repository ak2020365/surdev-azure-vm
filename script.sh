#!/usr/bin/env bash
#
# install-packer-azure-plugin.sh
#
# Purpose:
#   Install HashiCorp's Azure plugin for Packer either:
#     1) HCL2-native (preferred): generate/augment a required_plugins block and run `packer init`
#     2) Manual: use `packer plugins install` to place the binary in the plugins directory
#
# Requirements:
#   - Packer v1.7.0+ on PATH (for HCL2 + packer init / plugins). `packer version`
#   - Internet egress to download plugins (GitHub/releases.hashicorp.com)
#
# Usage:
#   ./install-packer-azure-plugin.sh --mode init   --version "~> 2.0" --workdir ./packer
#   ./install-packer-azure-plugin.sh --mode manual --version "2.1.0"
#
# Options:
#   --mode     init|manual   : init = write/merge required_plugins + packer init; manual = packer plugins install
#   --version  "<semver>"    : plugin version constraint (init) or exact version (manual). Examples: "~> 2.0" or "2.1.0"
#   --workdir  <path>        : directory containing your *.pkr.hcl files (only for --mode init). Default: current dir
#   --force                   : overwrite generated require file if present (init mode)
#   --plugin-name            : logical plugin name (default: azure). Rarely changed.
#   --source                 : plugin source address (default: github.com/hashicorp/azure)
#
# Exit codes:
#   0 = success, non-zero = error
#
set -euo pipefail

MODE=""
PLUGIN_VERSION=""
WORKDIR="$(pwd)"
FORCE="false"
PLUGIN_NAME="azure"
PLUGIN_SOURCE="github.com/hashicorp/azure"

usage() {
  grep '^#' "$0" | sed -e 's/^# \{0,1\}//'
}

log()  { echo "[INFO] $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$@"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)       MODE="${2:-}"; shift 2 ;;
    --version)    PLUGIN_VERSION="${2:-}"; shift 2 ;;
    --workdir)    WORKDIR="${2:-}"; shift 2 ;;
    --force)      FORCE="true"; shift 1 ;;
    --plugin-name) PLUGIN_NAME="${2:-}"; shift 2 ;;
    --source)     PLUGIN_SOURCE="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "Unknown argument: $1 (use -h)" ;;
  esac
done

[[ -z "$MODE" ]] || [[ "$MODE" == "init" ]] || [[ "$MODE" == "manual" ]] || die "--mode must be 'init' or 'manual'"
[[ -n "$PLUGIN_VERSION" ]] || die "--version is required"

require_cmd packer

case "$MODE" in
  init)
    # HCL2-native installation via required_plugins + packer init
    log "HCL2 mode selected (packer init). Workdir: $WORKDIR"

    [[ -d "$WORKDIR" ]] || die "--workdir '$WORKDIR' does not exist"
    cd "$WORKDIR"

    # Check for at least one *.pkr.hcl file (HCL2)
    HCL_COUNT=$(ls -1 *.pkr.hcl 2>/dev/null | wc -l | tr -d ' ')
    [[ "$HCL_COUNT" -gt 0 ]] || die "No *.pkr.hcl files found in '$WORKDIR'. HCL2 templates are required for 'packer init'."

    REQUIRE_FILE="packer.required_plugins.auto.pkr.hcl"

    if [[ -f "$REQUIRE_FILE" && "$FORCE" != "true" ]]; then
      log "Found existing $REQUIRE_FILE. (Use --force to overwrite.)"
    else
      log "Generating $REQUIRE_FILE with Azure plugin requirement..."
      cat > "$REQUIRE_FILE" <<EOF
packer {
  required_plugins {
    ${PLUGIN_NAME} = {
      source  = "${PLUGIN_SOURCE}"
      version = "${PLUGIN_VERSION}"
    }
  }
}
EOF
    fi

    log "Running 'packer init' to install required plugins..."
    # packer init installs plugins defined in required_plugins into the user plugins dir
    # Default dirs: ~/.config/packer/plugins (Unix), %APPDATA%\\packer.d\\plugins (Windows).
    # This is the recommended, supported flow as of Packer v1.7+.  [4](https://github.com/Azure/bicep/discussions/6629)[1](https://www.youtube.com/watch?v=kGDd2JTmpBg)
    packer init .

    log "Verifying plugin resolution..."
    # Lists required plugins + installed binaries that satisfy constraints
    packer plugins required . || true  # non-fatal if no extras
    log "Done. Azure plugin is ready for builds via required_plugins."
    ;;

  manual)
    # Manual install (when templates cannot be changed).
    # Note: plugin still needs to comply with any required_plugins constraints at build time.  [4](https://github.com/Azure/bicep/discussions/6629)
    log "Manual mode selected (packer plugins install)."

    # This will install into ~/.config/packer/plugins (Unix) by default; PATH not required.
    # You can set PACKER_PLUGIN_PATH to change the destination.  [3](https://learn.microsoft.com/en-us/azure/virtual-machines/shared-image-galleries)
    log "Installing Azure plugin ${PLUGIN_VERSION} from ${PLUGIN_SOURCE} ..."
    packer plugins install "${PLUGIN_SOURCE}" "${PLUGIN_VERSION}"

    log "Listing installed plugins (may include others):"
    # There is no single 'list' command in all versions, but show the folder if present
    PLUGDIR="${PACKER_PLUGIN_PATH:-$HOME/.config/packer/plugins}"
    if [[ -d "$PLUGDIR" ]]; then
      find "$PLUGDIR" -maxdepth 3 -type f -iname "*azure*" -print || true
    else
      log "Plugin directory not found at $PLUGDIR; your environment might differ."
    fi

    log "Note: HCL2 builds still consult the template's required_plugins for version checks." # [4](https://github.com/Azure/bicep/discussions/6629)
    ;;
esac
``