#!/usr/bin/bash
set -euo pipefail

script_path="$(readlink -f "${0}")"
script_dir="${script_path%/*}"

bin_dir="${script_dir}/bin"
mkdir -p "${bin_dir}"
ln -s "soxbeep/soxbeep.sh" "${bin_dir}"
ln -s "soxknock/soxknock.sh" "${bin_dir}"

echo "Add ${bin_dir} to your PATH variable."
