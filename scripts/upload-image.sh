#!/usr/bin/env bash
set -euo pipefail

# Downloads the .raw.xz from tfvars, decompresses on the runner, and uploads RAW to Proxmox dir storage as ISO content.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars="${repo_root}/terraform/terraform.tfvars"
workdir="${repo_root}/runner_artifacts"
mkdir -p "$workdir"
cd "$workdir"

tf_get() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$/\1/p" "$tfvars" | head -n1
}

pm_node="$(tf_get pm_node)"
dir_storage="$(tf_get PROXMOX_DIR_STORAGE)"
xz_url="$(tf_get talos_image_url)"
xz_name="$(tf_get talos_image_file_name)"     # *.raw.xz
raw_name="${xz_name%.xz}"                     # *.raw

base="${PROXMOX_VE_ENDPOINT%/api2/json}"
auth="Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"

# 1) download if needed
if [[ ! -f "$xz_name" ]]; then
  echo "Downloading: $xz_url"
  curl -L "$xz_url" -o "$xz_name"
fi

# 2) decompress if needed
if [[ ! -f "$raw_name" ]]; then
  echo "Decompressing: $xz_name -> $raw_name"
  xz -T0 -dv "$xz_name"   # produces $raw_name
fi

# 3) upload RAW to directory storage (stored at /var/lib/vz/template/iso/<raw_name>)
echo "Uploading ${raw_name} to ${dir_storage}:iso/${raw_name}"
curl -k -X POST \
  -H "$auth" \
  -F "content=iso" \
  -F "filename=@${raw_name};type=application/octet-stream;filename=${raw_name}" \
  "${base}/api2/json/nodes/${pm_node}/storage/${dir_storage}/upload"

echo "Upload complete."
