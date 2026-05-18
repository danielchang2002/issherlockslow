# issherlockslow — Sherlock filesystem I/O poller

A low-footprint poller that measures bandwidth and metadata performance across
`$HOME`, `$GROUP_HOME`, `$SCRATCH`, `$GROUP_SCRATCH`, and `$OAK` every 15 min,
logs results to a CSV on OAK, and publishes a rolling 7-day window to a
GitHub Pages dashboard at `issherlockslow`.

This directory **is** the GitHub repo. Polling scripts, dashboard, and a
synced JSON aggregate live together. The CSV archive stays on OAK only (gitignored).

## Quick start

```bash
# 1. On GitHub:
#    a. Create public repo named  issherlockslow  (leave it EMPTY)
#    b. Settings → Pages → Source: Deploy from a branch, Branch: main, Folder: /docs
#    c. Create a fine-grained PAT
#       (https://github.com/settings/tokens?type=beta)
#       - Repository access: only `issherlockslow`
#       - Permissions: Contents = Read and write

# 2. On Sherlock (one-time):
bash /oak/stanford/groups/brianhie/changdan/issherlockslow/setup.sh
# (prompts for your GitHub username + PAT, makes initial commit, pushes)

# 3. On Sherlock (start the poller):
sbatch /oak/stanford/groups/brianhie/changdan/issherlockslow/poll_io.sbatch

# 4. After ~1 minute:
#    https://<your-gh-user>.github.io/issherlockslow/
```

The SLURM job **auto-resubmits itself** ~2 min before walltime expires, so
once started it runs indefinitely without weekly manual intervention.

## Layout

```
issherlockslow/                 ← git repo, remote = github.com/<user>/issherlockslow
├── README.md                   this file
├── .gitignore
├── setup.sh                    one-time GitHub auth + initial push (entry point #1)
├── poll_io.sbatch              SLURM job, self-resubmitting (entry point #2)
├── test_io3.sh                 single-shot I/O probe (called by poll_io.sbatch)
├── aggregator.py               CSV → small JSON for dashboard
├── push_to_gh.sh               regenerate JSON + git push (called after each poll)
├── docs/                       ← GitHub Pages serves from here
│   ├── README.md               user-facing description of the dashboard
│   ├── index.html              Chart.js dashboard
│   └── data/latest.json        rolling 7-day window (overwritten each poll)
└── logs/                       (not in git — local archive only)
    ├── io_poll.csv             authoritative archive, grows forever, stays on OAK
    └── slurm-*.out             SLURM job stdout/stderr
```

## What gets measured

Each row of `logs/io_poll.csv`:

```
timestamp, host, fs, write_MBps, read_MBps, meta_create_ops_s, meta_unlink_ops_s, error
```

The dashboard plots only `write_MBps` and `meta_create_ops_s` — the two
independent contention axes (OST bandwidth and MDS metadata). The other
columns are kept for ad-hoc forensic analysis from the CSV on OAK.

## Footprint

- Per poll: ~3 s active, ~320 MB total I/O across 5 filesystems
- Per day: ~6 GB/FS, ~5 min total wall time
- Push to GitHub: 96/day, ~1 KB per commit, well below any abuse threshold

Several orders of magnitude below the noise floor of these filesystems.

## SLURM details

| setting | value | reason |
|---|---|---|
| `--partition` | `normal` | non-preemptible (won't randomly die); 7-day max walltime |
| `--time` | `7-00:00:00` | the max on `normal` |
| `--cpus-per-task` | 1 | poller is single-threaded |
| `--mem` | 2 GB | trivial; mostly for python + git |
| `--signal=B:TERM@120` | TERM sent 2 min before walltime ends | gives us time to resubmit cleanly |
| `--dependency=singleton` | only one `io_poll` job runs at once | safety against double submission |
| `--requeue` | requeue on preempt | belt-and-suspenders (`normal` doesn't preempt) |

**Auto-resubmit**: when the TERM trap fires (~120 s before walltime), the script
runs `sbatch poll_io.sbatch` for the next 7-day window then exits. The successor
is held by `dependency=singleton` until the current job finishes, then takes over.

To stop the poller for good:
```bash
scancel <current-jobid>
squeue -u $USER -n io_poll      # check for queued successor and scancel it too
```

## Investigating a slowdown

1. Spot the dip in the dashboard plot (write_MBps or meta_create_ops_s).
2. Note the timestamp.
3. On Sherlock:
   ```bash
   squeue -t RUNNING -o '%i %u %j %T %M %D %C'
   sacct -S <slowdown_time> -E <slowdown_time + 1h> -X \
         -o JobID,User,JobName,Elapsed,NCPUS,State
   ```
4. Cross-reference users / job names with the dropped filesystem.

The dashboard tells you *when* and *which FS*. The cross-reference tells you *who*.
