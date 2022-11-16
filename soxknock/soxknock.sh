#!/usr/bin/env bash
set -euo pipefail

declare -r sample_rate="44.1k"
declare -r bitdepth="24"

log() {
    echo "$(date +%T) $(basename "${0}"): ${1:-log() argument missing}"
}
log_err() {
    log "${1:-log_err() argument missing}" >&2
}
die() {
    log_err "${1-die() argument missing}"
    exit 1
}
die_usage() {
    log_err "${1-die() argument missing}"
    echo "" >&2
    usage
    exit 1
}
usage() {
    cat << EOF
Usage: $(basename "${0}") -o OUTPUT_FILE
Required:
  -o | --output OUTPUT_FILE     - output file

Optional:
  -f | --force                  - force overwrite
  -p | --pad PAD                - pad in samples            (default: 11025)
  -c | --count COUNT            - count                     (default: 1)
  -n | --norm NORM              - normalize level in dBFS   (default: -0.1)
  -b | --band BAND              - band                      (default: -2000)
  -d | --delay DELAY            - delay of the right channel in samples (default: 0)
  -h | --help                   - this help message

Generates ${bitdepth} / ${sample_rate} file.
EOF
}
declare -ra required_cmds=(sox bc)
for cmd in "${required_cmds[@]}"; do
    if ! which "${cmd}" >/dev/null 2>&1; then
        log "Required tools: ${required_cmds[*]}"
        die "Required tool not found: ${cmd}"
    fi
done

outfile=""
force="0"
pad="11025"
count="1"
norm="-0.1"
band="-2000"
delay="0"
while [ -n "${1-}" ]; do
    case "${1}" in
        -o|--outfile| \
        -p|--pad| \
        -c|--count| \
        -n|--norm| \
        -b|--band| \
        -d|--delay)
            if [ ! $# -ge 2 ]; then
                die_usage "Argument missing for option ${1}"
            fi
        ;;
    esac
    case "${1}" in
        -o|--outfile)
            outfile="${2}"
            shift
        ;;
        -f|--force)
            force="1"
        ;;
        -p|--pad)
            pad="${2}"
            shift
        ;;
        -c|--count)
            count="${2}"
            shift
        ;;
        -n|--norm)
            norm="${2}"
            shift
        ;;
        -b|--band)
            band="${2}"
            shift
        ;;
        -d|--delay)
            delay="${2}"
            shift
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            break
        ;;
    esac
    shift
done

if [ -z "${outfile}" ]; then
    die_usage "Output file is required."
fi
if [ -f "${outfile}" ] && [ "${force}" != "1" ]; then
    die "File ${outfile} already exists, use -f | --force option to overwrite."
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf ${tmp_dir}' EXIT

sinc_bw="$(echo "x=(${band} * -1); scale=0; x/1" | bc -l)"
if [ "${sinc_bw}" -le 1000 ]; then
    sinc_bw=400
fi
if [ "${sinc_bw}" -lt 22 ]; then
    sinc_bw=22
fi

sox -r"${sample_rate}" -c1 -n -b"${bitdepth}" "${tmp_dir}/knock1.wav" synth 1 sq trim 0 1s pad "${pad}s" "$((pad - 1))s" sinc -M -t "${sinc_bw}" "${band}" norm "${norm}" repeat "$((count - 1))"
if [ "${delay}" -eq 0 ]; then
    cp "${tmp_dir}/knock1.wav" "${tmp_dir}/knock2.wav"
elif [ "${delay}" -gt 0 ]; then
    sox "${tmp_dir}/knock1.wav" "${tmp_dir}/knock2.wav" pad "${delay}s" trim 0 "-${delay}s"
else
    delay=$((delay * -1))
    sox "${tmp_dir}/knock1.wav" "${tmp_dir}/knock2.wav" trim "${delay}s" pad 0 "${delay}s"
fi

sox -M "${tmp_dir}/knock1.wav" "${tmp_dir}/knock2.wav" "${outfile}"
