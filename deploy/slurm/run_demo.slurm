#!/bin/bash
#SBATCH -J qiita-explore-demo
#SBATCH --mail-type=NONE
#SBATCH --time=72:00:00
#SBATCH --partition=short
#SBATCH --ntasks=16
#SBATCH --nodes=1
#SBATCH --mem=64gb
#SBATCH --output=%x-%A_%a.out
#SBATCH --error=%x-%A_%a.err

# ============================================================
# qiita-explore demo launcher
# Pulls the container image from ghcr.io as an Apptainer SIF,
# starts gunicorn (API) and a static file server (frontend) on
# randomly-picked ports, then prints ready-to-use SSH tunnel
# instructions.  See deploy/slurm/README.md for full details.
# ============================================================

echo "============================================================"
echo "Job ID:     ${SLURM_JOB_ID}"
echo "Host:       $(hostname)"
echo "Start time: $(date)"
echo "============================================================"

# ------------------------------------------------------------
# 1. Source per-user secrets file if present
# ------------------------------------------------------------
if [[ -f "$HOME/.qiita-explore.env" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.qiita-explore.env"
fi

# ------------------------------------------------------------
# 2. Validate required environment variables
# ------------------------------------------------------------
_missing=0
for _var in API_KEY JWT_SECRET ADMIN_PASS QIITA_CONFIG_FP; do
    if [[ -z "${!_var}" ]]; then
        echo "ERROR: required environment variable \$${_var} is not set." >&2
        _missing=1
    fi
done
if [[ "$_missing" -eq 1 ]]; then
    echo "Set missing variables in ~/.qiita-explore.env or pass via:" >&2
    echo "  sbatch --export=ALL,API_KEY=...,JWT_SECRET=...,ADMIN_PASS=...,QIITA_CONFIG_FP=... deploy/slurm/run_demo.slurm" >&2
    exit 1
fi

# ------------------------------------------------------------
# 3. Pick two free ports on this compute node
# ------------------------------------------------------------
pick_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()'
}
APP_PORT=$(pick_port)
WEB_PORT=$(pick_port)

# ------------------------------------------------------------
# 4. Pull (or use cached) the Apptainer SIF image
# ------------------------------------------------------------
IMAGE_URL="${IMAGE_URL:-docker://ghcr.io/dhruvviveksharma/qiita-explore:latest}"
SIF_PATH="${SIF_CACHE_DIR:-$HOME/.apptainer-cache}/qiita-explore.sif"
mkdir -p "$(dirname "$SIF_PATH")"

echo "Pulling Apptainer image: ${IMAGE_URL}"
echo "  -> ${SIF_PATH}"
apptainer pull --force "$SIF_PATH" "$IMAGE_URL"

# ------------------------------------------------------------
# 5. Set up working and state directories
# ------------------------------------------------------------
WORKDIR="${SLURM_SUBMIT_DIR:-$PWD}"
STATE_DIR="${QIITA_EXPLORE_STATE:-$WORKDIR/.qiita-explore-state}"
mkdir -p "$STATE_DIR"

# ------------------------------------------------------------
# 6. Print SSH tunnel instructions (early so they appear in .out)
# ------------------------------------------------------------
NODE=$(hostname)
LOGIN_HOST="${LOGIN_HOST:-login.<cluster>.ucsd.edu}"
OUT_FILE="${SLURM_JOB_NAME}-${SLURM_JOB_ID}_0.out"

echo ""
echo "============================================================"
echo "qiita-explore demo running."
echo "============================================================"
echo "Compute node: ${NODE}"
echo "App port:     ${APP_PORT}  (gunicorn / Flask API)"
echo "Web port:     ${WEB_PORT}  (static frontend)"
echo ""
echo "From your LAPTOP, open an SSH reverse tunnel:"
echo ""
echo "  ssh -N -L 8080:${NODE}:${WEB_PORT} -L 8081:${NODE}:${APP_PORT} \\"
echo "      ${USER}@${LOGIN_HOST}"
echo ""
echo "Then visit:"
echo "  Frontend:  http://localhost:8080/"
echo "  API:       http://localhost:8081/api/"
echo ""
echo "Job ID:   ${SLURM_JOB_ID}"
echo "Logfile:  ${OUT_FILE}"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 7. Start gunicorn (API server) via Apptainer — background
# ------------------------------------------------------------
BASE_DATA_DIR="${BASE_DATA_DIR:-/ddn_scratch/d4sharma/qiita}"
mkdir -p "$BASE_DATA_DIR"

apptainer exec \
    --bind "$STATE_DIR:/var/lib/ezredbiom" \
    --bind "$QIITA_CONFIG_FP:/etc/qiita/qiita_config.cfg:ro" \
    --bind "${BASE_DATA_DIR:-/ddn_scratch/d4sharma/qiita}:${BASE_DATA_DIR:-/ddn_scratch/d4sharma/qiita}" \
    --env API_KEY="$API_KEY" \
    --env JWT_SECRET="$JWT_SECRET" \
    --env ADMIN_PASS="$ADMIN_PASS" \
    --env QIITA_CONFIG_FP=/etc/qiita/qiita_config.cfg \
    --env QIITA_EXPERIMENT_DB_PATH=/var/lib/ezredbiom/projects.db \
    --env PYTHONPATH=/app \
    "$SIF_PATH" \
    gunicorn -c /app/gunicorn_conf.py \
             --bind "0.0.0.0:${APP_PORT}" \
             --chdir /app/backend \
             run:app \
    > "$WORKDIR/gunicorn-${SLURM_JOB_ID}.log" 2>&1 &
APP_PID=$!

# ------------------------------------------------------------
# 8. Stage a writable copy of the frontend and patch the API base
# ------------------------------------------------------------
# The Docker image rewrites the API meta tag to "/api" for the
# nginx-proxied compose deploy. In SLURM we serve frontend and API on
# different ports (different origins from the browser), so we patch the
# meta tag to point directly at the local tunnel API port. CORS is
# enabled on the Flask side, so cross-origin works.
LOCAL_API_PORT="${LOCAL_API_PORT:-8081}"
FRONTEND_STAGE="$WORKDIR/.qiita-explore-frontend"
rm -rf "$FRONTEND_STAGE"
mkdir -p "$FRONTEND_STAGE"
apptainer exec \
    --bind "$FRONTEND_STAGE:/out" \
    "$SIF_PATH" \
    cp -r /app/frontend/. /out/
sed -i \
    "s|<meta name=\"api-base\" content=\"[^\"]*\">|<meta name=\"api-base\" content=\"http://localhost:${LOCAL_API_PORT}/api\">|" \
    "$FRONTEND_STAGE/index.html"

# ------------------------------------------------------------
# 9. Start static frontend server (host python3, serves staged copy)
# ------------------------------------------------------------
python3 -m http.server "$WEB_PORT" --directory "$FRONTEND_STAGE" \
    > "$WORKDIR/frontend-${SLURM_JOB_ID}.log" 2>&1 &
WEB_PID=$!

# ------------------------------------------------------------
# 10. Trap for clean shutdown when SLURM terminates the job
# ------------------------------------------------------------
cleanup() {
    echo "Shutting down (signal received)..."
    kill -TERM "$APP_PID" "$WEB_PID" 2>/dev/null
    wait "$APP_PID" "$WEB_PID" 2>/dev/null
}
trap cleanup TERM INT EXIT

# ------------------------------------------------------------
# 11. Wait — block until both children exit (or job is killed)
# ------------------------------------------------------------
wait "$APP_PID" "$WEB_PID"
