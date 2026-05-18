for fs in $HOME $GROUP_HOME $SCRATCH $GROUP_SCRATCH $OAK; do
    echo "=== Testing $fs ==="
    dd if=/dev/zero of=$fs/testfile_$$ bs=1M count=512 oflag=direct 2>&1 | grep -E "copied|GB/s|MB/s"
    rm -f $fs/testfile_$$
done
