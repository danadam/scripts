#!/usr/bin/env bash
set -euo pipefail



sox_rate="${SOX_RATE:-44100}"
sox_bitdepth="${SOX_BITDEPTH:-24}"



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
    usage
    exit 1
}

bcdo() {
    echo "scale=8; ${*}" | bc -l
}

fromdbfs() {
    local dbfs="${1}"
    echo "fromdbfs( ${dbfs} )" | bc -l <(cat <<EOF
define l10(x) { return l(x)/l(10) }
define pow(x,y) { return e(y * l(x)) }
define fromdbfs(x) { return pow(10,x/20) }
EOF
)
}

todbfs() {
    local linear="${1}"
    echo "todbfs( ${linear} )" | bc -l <(cat <<EOF
define l10(x) { return l(x)/l(10) }
define todbfs(x) { return 20*l10(x) }
EOF
)
}

default_amplitude="-20"
arg_output=""
arg_force_overwrite="no"
arg_amplitude=""
arg_peak_sample=""
arg_duration="5"
arg_frequency="440"
arg_type="square"

usage() {
    cat << EOF
Usage:
  $(basename "${0}") -o FILENAME

  Required:
    -o | --output FILENAME              - output filename

  Optional:
    -f | --force                        - force overwrite
    -a | --amplitude AMPLITUDE_DBFS     - amplitude of the wave in dBFS (samples may exceed it, default: ${default_amplitude})
    -A | --peak-sample AMPLITUDE_DBFS   - peak sample in dBFS
    -d | --duration DURATION            - duration in SoX format (default: ${arg_duration})
    -F | --frequency FREQUENCY          - frequency in Hz (default: ${arg_frequency})
    -t | --type TYPE                    - type (default: ${arg_type})
    -h | --help                         - this help message

Generates bandlimited wave of type TYPE: square, triangle, saw, reversedsaw.

Duration accepts sox format.

--amplitude and --peak-sample are mutually exclusive.
EOF
}
declare -ra required_cmds=(sox bc)
for cmd in "${required_cmds[@]}"; do
    if ! which "${cmd}" >/dev/null 2>&1; then
        log "Required tools: ${required_cmds[*]}"
        die "Required tool not found: ${cmd}"
    fi
done

while [ -n "${1-}" ]; do
    case "${1}" in
        -o|--output| \
        -a|--amplitude| \
        -A|--peak-sample| \
        -d|--duration| \
        -F|--frequency| \
        -t|--type)
            if [ ! $# -ge 2 ]; then
                die_usage "Argument missing for option ${1}"
            fi
        ;;
    esac
    case "${1}" in
        -o|--output)
            arg_output="${2}"
            shift
        ;;
        -f|--force)
            arg_force_overwrite="YES"
        ;;
        -a|--amplitude)
            arg_amplitude="${2}"
            shift
        ;;
        -A|--peak-sample)
            arg_peak_sample="${2}"
            shift
        ;;
        -d|--duration)
            arg_duration="${2}"
            shift
        ;;
        -F|--frequency)
            arg_frequency="${2}"
            shift
        ;;
        -t|--type)
            arg_type="${2}"
            shift
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            die_usage "Unknown command line argument: ${1}"
        ;;
    esac
    shift
done

if [ -z "${arg_output}" ]; then
    die_usage "Output file is required."
fi
if [ -f "${arg_output}" ] && [ "${arg_force_overwrite}" != "YES" ]; then
    die "File ${arg_output} already exists. Use -f | --force to overwrite."
fi
if [ -n "${arg_amplitude}" ] && [ -n "${arg_peak_sample}" ]; then
    die_usage "-a | --amplitude and -A | --peak-sample are mutually exclusive"
fi
if [ -n "${arg_amplitude}" ] && [ "${arg_amplitude}" != "0" ] && [[ ! "${arg_amplitude}" =~ ^-[0-9.]+$ ]]; then
    die_usage "Invalid amplitude: ${arg_amplitude}"
fi
if [ -n "${arg_peak_sample}" ] && [ "${arg_peak_sample}" != "0" ] && [[ ! "${arg_peak_sample}" =~ ^-[0-9.]+$ ]]; then
    die_usage "Invalid peak sample: ${arg_peak_sample}"
fi
if [[ ! "${arg_duration}" =~ ^[0-9:.]+$ ]]; then
    die_usage "Invalid duration: ${arg_duration}"
fi
if [[ ! "${arg_frequency}" =~ ^[0-9.]+$ ]]; then
    die_usage "Invalid frequency: ${arg_frequency}"
fi
if [[ ! "${arg_type}" =~ ^(square|triangle|saw|reversedsaw)$ ]]; then
    die_usage "Invalid type: ${arg_type}"
fi



bw=$(bcdo "0.91 * ${sox_rate} / 2")     # 0.91 gives 20'065 Hz bandwidth for 44'100 sampling frequency
hmax=$(bcdo "scale=0; (${bw} - ${arg_frequency}) / ${arg_frequency} + 1")
echo "bw=${bw}, hmax=${hmax}"
echo

declare -a synth_args=()
remix_arg=""
remix_arg_sep=""

case "${arg_type}" in
    square)
        # it is 4/pi, but pi=4*a(1), so
        amplitude_coeff="1 / a(1)"

        for h in $(seq 1 2 "${hmax}"); do
            ch=$(( (h+1)/2 ))
            synth_args+=( "sin" "$(bcdo "$h * $arg_frequency")" )
            remix_arg+="${remix_arg_sep}${ch}v$(bcdo "1 / $h")"
            remix_arg_sep=","
        done
    ;;
    triangle)
        # it is 8/pi^2, but pi=4*a(1), so
        amplitude_coeff="1 / (2 * a(1) * a(1))"

        for h in $(seq 1 2 "${hmax}"); do
            ch=$(( (h+1)/2 ))
            synth_args+=( "sin" "$(bcdo "$h * $arg_frequency")" )
            remix_arg+="${remix_arg_sep}${ch}v$(bcdo "-1^($ch-1) / $h^2")"
            remix_arg_sep=","
        done
    ;;
    saw)
        # it is 2/pi, but pi=4*a(1), so
        amplitude_coeff="1 / (2*a(1))"

        for h in $(seq 1 "${hmax}"); do
            ch=$h
            synth_args+=( "sin" "$(bcdo "$h * $arg_frequency")" )
            remix_arg+="${remix_arg_sep}${ch}v$(bcdo "-1^($h-1) / $h")"
            remix_arg_sep=","
        done
    ;;
    reversedsaw)
        # it is 2/pi, but pi=4*a(1), so
        amplitude_coeff="1 / (2*a(1))"

        for h in $(seq 1 "${hmax}"); do
            ch=$h
            synth_args+=( "sin" "$(bcdo "$h * $arg_frequency")" )
            remix_arg+="${remix_arg_sep}${ch}v$(bcdo "-1^$h / $h")"
            remix_arg_sep=","
        done
    ;;
esac

if [ -n "${arg_peak_sample}" ]; then
    norm1_arg=""
    norm2_arg="norm ${arg_peak_sample}"
else
    if [ -z "${arg_amplitude}" ]; then
        arg_amplitude="${default_amplitude}"
    fi
    linear_amplitude="$(fromdbfs "${arg_amplitude}")"
    norm1_arg="norm $(todbfs "${linear_amplitude} * ${amplitude_coeff}")"
    norm2_arg=""
fi

echo "synth: ${synth_args[*]}"
echo
echo "remix: $remix_arg"
echo
echo "norm1: $norm1_arg"
echo "norm2: $norm2_arg"

sox "-r${sox_rate}" -n "-b${sox_bitdepth}" "${arg_output}" synth "${arg_duration}" "${synth_args[@]}" ${norm1_arg} remix "${remix_arg}" ${norm2_arg} dither

