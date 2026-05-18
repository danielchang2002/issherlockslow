# Is Sherlock Slow?

A live dashboard of I/O performance on Stanford's [Sherlock](https://www.sherlock.stanford.edu/) cluster, polled every 15 minutes.

**Live site:** https://&lt;your-gh-user&gt;.github.io/issherlockslow/

## What it shows

Two time-series plots covering the last 7 days, one line per filesystem:

| Plot | Metric | What it captures |
|---|---|---|
| **Bandwidth** | `write_MBps` | OST (data-server) throughput. Drops here = someone is hammering the storage with heavy sequential I/O. |
| **Metadata** | `meta_create_ops_s` | MDS (metadata-server) throughput. Drops here = someone is doing millions of small-file ops; this is the most common user-visible "the FS is slow today" symptom. |

Red markers mark probe errors (timeout, FS unavailable, etc.).

Filesystems monitored: `$HOME`, `$GROUP_HOME`, `$SCRATCH`, `$GROUP_SCRATCH`, `$OAK`.

## How to read it

- **Eyeball the slope:** a single dip is probably noise (shared FS, single-stream probe). Sustained drops across multiple polls are the real signal.
- **Compare across filesystems:** if all five drop at once → cluster-wide / network-side issue. If only one drops → contention on that FS specifically.
- **Cross-check time of incident** with `squeue -t RUNNING` and `sacct -S <slowdown_time>` to identify candidate culprit jobs.

## Methodology and caveats

- **Single-node, single-stream measurement.** Probes run from one SLURM compute node with `dd` at 4 MB block size, O_DIRECT, fsync. Real peak bandwidth on parallel filesystems (Lustre) is much higher than these numbers — what we measure is *relative* load, not absolute capacity.
- **Numbers are noisy.** Single-shot per poll; expect 2–3× run-to-run variance even on a quiet FS. Trends matter, single samples don't.
- **Probe is non-disruptive.** ~32 MB write + 32 MB read + 50 file create/unlink per FS per poll → ~3 s of activity every 15 min. Orders of magnitude below the noise floor of these filesystems.
- **Read throughput may be inflated** by server-side cache (the read happens immediately after the write of the same file). Reads are kept as a corroborating signal but not plotted.
- **15-minute polling cadence.** Hour-long slowdowns: clearly visible. Multi-minute bursts: may be missed.
- **No alerting.** This is a monitoring dashboard, not a paging system.

## Pipeline

```
test_io3.sh on Sherlock --(every 15 min)--> io_poll.csv (on OAK, append-only)
                                                |
                          aggregator.py (filter last 7d, reshape to columnar JSON)
                                                |
                                       data/latest.json (in this repo)
                                                |
                              git push to GitHub --> GitHub Pages --> your browser
```

Source CSV (full archive) lives on Sherlock at `/oak/stanford/groups/brianhie/changdan/issherlockslow/logs/io_poll.csv`.
Dashboard sees only the rolling 7-day window.

The poller, aggregator, and dashboard source all live in the same repo
(this is the `docs/` subdirectory; the polling scripts are at the repo root).

## Maintained by

Stanford / Brian Hie lab.
