# SLURM Demo Launcher — qiita-explore

This directory contains a SLURM batch script for running a live demo of
**qiita-explore** on a UCSD SLURM cluster (e.g., barnacle, triton, or expanse).
The script pulls `ghcr.io/dhruvviveksharma/qiita-explore:latest` as an Apptainer SIF,
starts gunicorn (Flask API) and a static file server (frontend) on
randomly-chosen ports on the compute node, and prints a ready-to-paste SSH
reverse-tunnel command so you can reach the app from your laptop. This is a
convenience demo path, not a production deployment — for production, see
[`deploy/DEPLOY.md`](../DEPLOY.md).

---

## Prerequisites

- A cluster account with SSH access to the login node.
- Apptainer (or Singularity) available on compute nodes. On many UCSD clusters
  you activate it with `module load apptainer`; check with `module avail
  apptainer` or `module avail singularity`. Apptainer and Singularity share
  the same CLI for these commands — if your cluster has `singularity` but not
  `apptainer`, replace `apptainer` with `singularity` in the script.
- The lab's `qiita_config.cfg` file somewhere readable on the cluster (e.g.,
  your home directory).
- SSH access to the cluster login node from your laptop.

---

## One-time setup

### 1. Place `qiita_config.cfg` on the cluster

```bash
scp /path/to/qiita_config.cfg <user>@<login-node>:~/qiita_config.cfg
```

### 2. Create `~/.qiita-explore.env` on the cluster

```bash
cat > ~/.qiita-explore.env << 'EOF'
export API_KEY=<NRP-Nautilus LLM token>
export JWT_SECRET=$(openssl rand -hex 32)
export ADMIN_PASS=<strong password>
export QIITA_CONFIG_FP=$HOME/qiita_config.cfg
export LOGIN_HOST=<your cluster login node hostname>
EOF
chmod 600 ~/.qiita-explore.env
```

Replace the angle-bracket placeholders with real values. `LOGIN_HOST` is the
hostname you SSH to from your laptop (e.g., `barnacle.ucsd.edu`). The file
contains secrets — keep permissions at `600`.

---

## Submit the job

Clone the repo (or copy just this directory) onto the cluster, then run:

```bash
sbatch deploy/slurm/run_demo.slurm
```

Log files (`qiita-explore-demo-<jobid>_0.out` and `.err`) are written to the
directory you ran `sbatch` from.

---

## Connect from your laptop

### 1. Watch the job output for tunnel instructions

```bash
tail -f qiita-explore-demo-<jobid>_0.out
```

The script prints the exact SSH command near the top of that file, shortly
after the image pull finishes. It looks like:

```
ssh -N -L 8080:<node>:<WEB_PORT> -L 8081:<node>:<APP_PORT> \
    <user>@<LOGIN_HOST>
```

### 2. Run that command on your laptop

Leave the SSH process running in a terminal. It will block silently — that is
normal.

### 3. Open your browser

| URL | What you get |
|-----|--------------|
| `http://localhost:8080/` | React/static frontend |
| `http://localhost:8081/api/` | Flask API (gunicorn) |

The launcher patches the served `index.html` so the frontend calls the
API at `http://localhost:8081/api`. Your tunnel must therefore keep
`localhost:8081` mapped to the gunicorn port (the example above already
does). If you want to use a different local port, set
`LOCAL_API_PORT` in `~/.qiita-explore.env` before submitting.

---

## Caveats

- **Walltime vs. partition**: the script requests 72 hours on `--partition=short`.
  Most SLURM `short` partitions cap at 24 hours or less. If the job is rejected,
  change the partition to one that allows longer walltimes (e.g.,
  `--partition=hotel`, `--partition=long`, or whatever your cluster provides).
  Edit `#SBATCH --partition=` and `#SBATCH --time=` accordingly.

- **Apptainer SIF cache**: the SIF is cached at
  `~/.apptainer-cache/qiita-explore.sif` (about 1–2 GB). If your home quota
  is tight, set `SIF_CACHE_DIR` to a scratch path before submitting:
  ```bash
  export SIF_CACHE_DIR=/scratch/$USER/apptainer-cache
  sbatch deploy/slurm/run_demo.slurm
  ```

- **`--force` pull**: the script always re-pulls the image (`apptainer pull
  --force`), so you get the latest tag on every run. If the image rarely
  changes and your network is slow, comment out `--force` and do a one-time
  pull manually.

- **Single viewer**: the SSH tunnel is tied to your laptop. For multi-viewer
  demos, tunnel to a shared machine or use a VPN instead.

- **No HTTPS / no nginx**: gunicorn serves the API directly and Python's
  `http.server` serves the frontend. This is intentional for a quick demo.
  For production, see `deploy/DEPLOY.md`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `apptainer: command not found` | Run `module load apptainer` (or `module load singularity`) before submitting, or add it to your `~/.bashrc` / submit script. |
| `Permission denied` writing SIF | Your `$HOME` or `SIF_CACHE_DIR` is read-only on the compute node. Override: `export SIF_CACHE_DIR=/scratch/$USER/apptainer-cache`. |
| SSH tunnel connects but page is blank | The API may have failed to start. Check `gunicorn-<jobid>.log` in your submit directory for Python tracebacks; likely a `qiita_config.cfg` path or DB connectivity issue. |
| Job rejected at submission | Partition walltime limit exceeded. Change `--partition` and/or `--time` in the script header. |
| Ports appear in use | Extremely unlikely (random ephemeral ports), but re-submit to get new ports. |
