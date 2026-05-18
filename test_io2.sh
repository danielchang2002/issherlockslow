#!/bin/bash
# Minimal IO test: direct write + direct read, ~256MB per fs
SIZE=256  # MB

for fs in $HOME $GROUP_HOME $SCRATCH $GROUP_SCRATCH $OAK; do
    [[ -d $fs && -w $fs ]] || continue
    f=$fs/.iotest_$$
    w=$(dd if=/dev/zero of=$f bs=4M count=$((SIZE/4)) \
           oflag=direct conv=fsync 2>&1 | awk '/copied/{print $(NF-1), $NF}')
    r=$(dd if=$f of=/dev/null bs=4M iflag=direct 2>&1 \
           | awk '/copied/{print $(NF-1), $NF}')
    rm -f $f
    printf "%-40s  write: %-12s  read: %-12s\n" "$fs" "$w" "$r"
done
