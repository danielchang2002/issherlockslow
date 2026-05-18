#!/bin/bash
# Single-shot I/O probe. Appends one CSV row per filesystem to $LOG.
# Designed to be called every 15 min from a SLURM polling job.

set -u

SIZE_MB=32
TIMEOUT=60
META_N=50
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG="$LOG_DIR/io_poll.csv"

mkdir -p "$LOG_DIR"
if [[ ! -s "$LOG" ]]; then
    echo "timestamp,host,fs,write_MBps,read_MBps,meta_create_ops_s,meta_unlink_ops_s,error" >> "$LOG"
fi

HOST=$(hostname -s)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TEMPS=()
cleanup() {
    local f
    for f in "${TEMPS[@]:-}"; do
        [[ -n "$f" ]] && rm -rf "$f" 2>/dev/null
    done
}
trap cleanup EXIT INT TERM

declare -A FS_MAP=(
    [HOME]="${HOME:-}"
    [GROUP_HOME]="${GROUP_HOME:-}"
    [SCRATCH]="${SCRATCH:-}"
    [GROUP_SCRATCH]="${GROUP_SCRATCH:-}"
    [OAK]="${OAK:-}"
)
ORDER=(HOME GROUP_HOME SCRATCH GROUP_SCRATCH OAK)

parse_dd() {
    awk '/copied/ {
        v = $(NF-1); u = $NF
        if (u ~ /GB/) v *= 1024
        else if (u ~ /KB/) v /= 1024
        printf "%.1f", v
        exit
    }'
}

for name in "${ORDER[@]}"; do
    fs="${FS_MAP[$name]}"
    w=""; r=""; mc=""; mu=""; err=""

    if [[ -z "$fs" || ! -d "$fs" || ! -w "$fs" ]]; then
        printf "%s,%s,%s,,,,,unavailable\n" "$TS" "$HOST" "$name" >> "$LOG"
        continue
    fi

    probe="$fs/.iopoll_${HOST}_$$"
    metadir="${probe}.meta"
    TEMPS+=("$probe" "$metadir")

    w=$(timeout "$TIMEOUT" dd if=/dev/zero of="$probe" bs=4M count=$((SIZE_MB/4)) \
            oflag=direct conv=fsync 2>&1 | parse_dd) || true
    [[ -z "$w" ]] && err="write_fail"

    if [[ -z "$err" ]]; then
        r=$(timeout "$TIMEOUT" dd if="$probe" of=/dev/null bs=4M iflag=direct 2>&1 | parse_dd) || true
        [[ -z "$r" ]] && err="read_fail"
    fi
    rm -f "$probe"

    if [[ -z "$err" ]]; then
        mkdir -p "$metadir"
        t0=$(date +%s.%N)
        for i in $(seq 1 $META_N); do : > "$metadir/f$i"; done
        t1=$(date +%s.%N)
        for i in $(seq 1 $META_N); do rm -f "$metadir/f$i"; done
        t2=$(date +%s.%N)
        rmdir "$metadir" 2>/dev/null

        mc=$(awk -v n=$META_N -v a=$t0 -v b=$t1 'BEGIN{printf "%.1f", n/(b-a)}')
        mu=$(awk -v n=$META_N -v a=$t1 -v b=$t2 'BEGIN{printf "%.1f", n/(b-a)}')
    fi

    printf "%s,%s,%s,%s,%s,%s,%s,%s\n" "$TS" "$HOST" "$name" "$w" "$r" "$mc" "$mu" "$err" >> "$LOG"
done
