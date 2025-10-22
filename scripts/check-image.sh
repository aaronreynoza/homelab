#!/usr/bin/env bash
set -euo pipefail

# Reads pm_node, PROXMOX_DIR_STORAGE, talos_image_file_name from terraform/terraform.tfvars
# Uses PROXMOX_VE_ENDPOINT (…/api2/json) + token env to check if RAW is already uploaded
# Emits image_present=true/false to $GITHUB_OUTPUT

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${repo_root}/terraform/terraform.tfvars"

# tiny tfvars parser: key = "value"
tf_get() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$tfvars" | head -n1
}

pm_node="$(tf_get pm_node)"
dir_storage="$(tf_get PROXMOX_DIR_STORAGE)"
xz_name="$(tf_get talos_image_file_name)"         # e.g. talos-...raw.xz
raw_name="${xz_name%.xz}"                         # -> talos-...raw

# derive base URL and host from PROXMOX_VE_ENDPOINT (which ends with /api2/json)
# base becomes: https://host:8006
base="${PROXMOX_VE_ENDPOINT%/api2/json}"

auth="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

# list ISO content on the directory storage
resp="$(curl -sS -k -H "$auth" \
  "${base}/api2/json/nodes/${pm_node}/storage/${dir_storage}/content?content=iso")"

match="${dir_storage}:iso/${raw_name}"
present="$(echo "$resp" | jq -r '.data[].volid' | grep -Fx "${match}" || true)"

if [[ -n "$present" ]]; then
  echo "Found image: ${match}"
  echo "image_present=true" >> "$GITHUB_OUTPUT"
else
  echo "Image not found: ${match}"
  echo "image_present=false" >> "$GITHUB_OUTPUT"
fi
