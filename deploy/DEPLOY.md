# EZREDBIOM — VM Deployment Runbook

Single-VM Docker Compose deployment for ezredbiom. The app connects to the
lab's existing Qiita Postgres + Redis (no DB shipped in the image).

## Architecture (on the VM)

```
Internet → :80 nginx → app:5001 (gunicorn, Flask) → lab Postgres + Redis
                                                   → NRP-Nautilus LLM API
```

## Prerequisites

- A Linux VM the lab controls (Ubuntu 22.04 LTS or similar).
- Network egress to:
  - the lab's PostgreSQL host (whatever `qiita_config.cfg` points at)
  - the lab's Redis host
  - `https://ellm.nrp-nautilus.io` (LLM API)
- The lab's working `qiita_config.cfg` file.
- DNS A record (or CNAME) eventually pointing the chosen domain at the VM.


## One-Time VM Setup

```bash
ssh ubuntu@<vm-ip>

# Docker + compose plugin
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin git
sudo usermod -aG docker $USER
newgrp docker
docker compose version    # should print v2.x
```


## Deploy

```bash
# 1. Clone the repo
git clone <repo-url> qiita-web
cd qiita-web

# 2. Drop in the lab Qiita config
mkdir -p deploy/secrets
scp lab-admin:qiita_config.cfg deploy/secrets/qiita_config.cfg
chmod 600 deploy/secrets/qiita_config.cfg

# 3. Configure runtime env
cp deploy/.env.example deploy/.env
vim deploy/.env
#   API_KEY=<NRP-Nautilus token>
#   JWT_SECRET=<openssl rand -hex 32>
#   ADMIN_PASS=<strong password>

# 4. Build and start
docker compose -f deploy/docker-compose.yml build
docker compose -f deploy/docker-compose.yml up -d
docker compose -f deploy/docker-compose.yml ps           # both services should be "running"
docker compose -f deploy/docker-compose.yml logs -f app  # tail until ready
```


## Smoke Test

From the VM itself:

```bash
curl -s http://localhost/ | head -5
curl -s http://localhost/api/studies/first | head -c 200
```

From your laptop:

```bash
curl -s http://<vm-ip>/api/studies/first | head -c 200
```


## Go Live

- Ask the lab admin to add an A record:
  ```
  ezredbiom.<lab-domain>   →   <vm-ip>
  ```
- Verify: `curl -s http://ezredbiom.<lab-domain>/api/studies/first`


## Add TLS (recommended next step)

Easy path — let certbot manage Let's Encrypt certs:

```bash
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d ezredbiom.<lab-domain>
# certs land in /etc/letsencrypt/live/ezredbiom.<lab-domain>/
```

- In `deploy/docker-compose.yml`: uncomment the `443:443` port mapping and add:
  ```yaml
    - /etc/letsencrypt:/etc/letsencrypt:ro
  ```
- In `deploy/nginx/nginx.conf`: uncomment the TLS server block and update
  `server_name` + cert paths.

```bash
docker compose -f deploy/docker-compose.yml up -d nginx
```

Alternative: replace the nginx service with Caddy — it auto-issues + renews
Let's Encrypt certs once DNS resolves to the VM.


## Operations

| Task | Command |
|------|---------|
| Logs | `docker compose -f deploy/docker-compose.yml logs -f app` |
| Nginx logs | `docker compose -f deploy/docker-compose.yml logs -f nginx` |
| Restart | `docker compose -f deploy/docker-compose.yml restart app` |
| Update code | `git pull && docker compose -f deploy/docker-compose.yml build && docker compose -f deploy/docker-compose.yml up -d` |
| Backup state | `docker run --rm -v ezredbiom_ezredbiom_data:/data -v $PWD:/backup alpine tar czf /backup/projects-$(date +%F).tar.gz -C /data .` |
| Tear down (keep volumes) | `docker compose -f deploy/docker-compose.yml down` |
| Tear down (WIPE SQLite store) | `docker compose -f deploy/docker-compose.yml down -v` |


## Troubleshooting

**"API_KEY env var required"**
- `deploy/.env` file missing or not loaded. Confirm `docker compose -f deploy/docker-compose.yml config` shows your `.env` values.

**"psycopg2.OperationalError: could not connect to server"**
- `deploy/secrets/qiita_config.cfg` has wrong Postgres host/credentials, or VM lacks
  network egress to lab Postgres. Check from inside the container:
  ```bash
  docker compose -f deploy/docker-compose.yml exec app sh -c \
    'python -c "from qiita_db.sql_connection import TRN; print(\"ok\")"'
  ```

**Frontend loads but API calls 502**
- nginx can't reach app. Check:
  ```bash
  docker compose -f deploy/docker-compose.yml exec nginx wget -qO- http://app:5001/api/studies/first
  ```

**LLM streams hang or cut off mid-response**
- Confirm `proxy_buffering off` in `deploy/nginx/nginx.conf` and `gunicorn timeout=120` in `deploy/gunicorn_conf.py`.
