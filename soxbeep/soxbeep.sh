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
Usage: $(basename "${0}") -o OUTPUT_FILE -F FREQ
Required:
  -o | --output OUTPUT_FILE     - output file
  -F | --freq FREQ              - beep tone frequency

Optional:
  -f | --force                  - force overwrite
  -l | --length LENGTH          - length of a single beep in seconds    (default: 1.0)
  -d | --duty DUTY              - duty cycle, a part of LENGTH the tone is on,
                                  including fade-in and fade-out        (default: 0.5)
  -c | --count COUNT            - number of beeps                       (default: 1)
  -n | --norm NORM              - normalize level in dBFS               (default: -0.1)
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
tone_freq=""
length="1"
duty="0.5"
count="1"
norm="-0.1"

while [ -n "${1-}" ]; do
    case "${1}" in
        -o|--outfile| \
        -F|--freq| \
        -l|--length| \
        -d|--duty| \
        -c|--count| \
        -n|--norm)
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
        -F|--freq)
            tone_freq="${2}"
            shift
        ;;
        -l|--length)
            length="${2}"
            shift
        ;;
        -d|--duty)
            duty="${2}"
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

if [ -z "${tone_freq}" ]; then
    die_usage "Tone frequency is required."
fi
if [ -z "${outfile}" ]; then
    die_usage "Output file is required."
fi
if [ -f "${outfile}" ] && [ "${force}" != "1" ]; then
    die "File ${outfile} already exists, use -f | --force option to overwrite."
fi

synth_length="$(echo "${length} * ${duty}" | bc -l)"
pad="$(echo "${length} - ${synth_length}" | bc -l)"
fade="$(echo "${synth_length} * 0.05" | bc -l)"

#set -x
sox -r"${sample_rate}" -c1 -n -b"${bitdepth}" "${outfile}" synth "${synth_length}" sin "${tone_freq}" norm "${norm}" fade h "${fade}" 0 "${fade}" pad 0 "${pad}" repeat $((count - 1))
