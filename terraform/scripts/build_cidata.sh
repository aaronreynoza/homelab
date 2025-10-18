#!/usr/bin/env bash
set -euo pipefail
# Usage: build_cidata.sh <ssh_host> <vm_name> <cluster_endpoint> <cluster_name>
SSH_HOST="${1}"
VM_NAME="${2}"
CLUSTER_EP="${3}"
CLUSTER_NAME="${4}"

ISO_DIR="/var/lib/vz/template/iso"
ISO="${ISO_DIR}/${VM_NAME}-cidata.iso"

# user-data for Talos (very small bootstrap; the real cluster config will be applied later)
read -r -d '' USERDATA <<'YAML'
#cloud-config
hostname: ${VM_NAME}
ssh_authorized_keys:
  - ${SSH_PUBKEY}
YAML

# meta-data is required by NoCloud (empty hostname is fine)
read -r -d '' METADATA <<'YAML'
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
YAML

# Expand variables that came from the environment
USERDATA="${USERDATA//\$\{VM_NAME\}/${VM_NAME}}"
USERDATA="${USERDATA//\$\{SSH_PUBKEY\}/${SSH_PUBKEY:-}}"
METADATA="${METADATA//\$\{VM_NAME\}/${VM_NAME}}"

ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "${SSH_HOST}" bash -s <<'REMOTE' "${ISO_DIR}" "${ISO}" "${USERDATA}" "${METADATA}"
set -euo pipefail
ISO_DIR="\$1"; ISO="\$2"; USERDATA="\$3"; METADATA="\$4"
mkdir -p "\$ISO_DIR"
tmpd="\$(mktemp -d)"; trap 'rm -rf "\$tmpd"' EXIT
printf "%s" "\$USERDATA" > "\$tmpd/user-data"
printf "%s" "\$METADATA" > "\$tmpd/meta-data"
# Prefer cloud-localds if present, else genisoimage
if command -v cloud-localds >/dev/null 2>&1; then
  cloud-localds "\$ISO" "\$tmpd/user-data" --metadata "\$tmpd/meta-data"
else
  genisoimage -output "\$ISO" -volid cidata -joliet -rock "\$tmpd/user-data" "\$tmpd/meta-data" >/dev/null 2>&1
fi
ls -lh "\$ISO"
REMOTE
