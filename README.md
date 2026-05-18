# Hermes Agent — Coolify Deployment Kit

**Build from Dockerfile · Hermes Desktop Ready · Multi-Profile**

> Upstream: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)  
> Desktop client: [fathah/hermes-desktop](https://github.com/fathah/hermes-desktop)

---

## What's in this repo

```
hermes-coolify/
├── Dockerfile                  ← Builds hermes-agent from source (clones upstream)
├── docker-compose.coolify.yml  ← Coolify-adapted compose (bridge network, API server on)
├── .env.example                ← All environment variables with documentation
├── init-hermes.sh              ← First-time setup script (run once on the server)
└── README.md                   ← This file
```

The `Dockerfile` clones `hermes-agent` from GitHub at build time — you do not need to
check out the upstream source yourself. Coolify points to this repo, builds the image,
and runs it with your config.

---

## Architecture

```
  Your Machine
  ┌─────────────────────────────────────────┐
  │  Hermes Desktop (Electron app)           │
  │  ← chat · sessions · profiles · skills  │
  └──────────────┬──────────────────────────┘
                 │ HTTPS (API_SERVER_KEY auth)
                 ▼
  Coolify Server
  ┌─────────────────────────────────────────┐
  │  hermes-gateway  (port 8642)            │
  │  └── OpenAI-compatible API server       │
  │  └── Gateway (Telegram / Discord / …)   │
  │                                         │
  │  hermes-dashboard  (port 9119, optional)│
  │  └── Web UI served via Caddy + SSL      │
  │                                         │
  │  Volume: /data/hermes → /opt/data       │
  │  └── .env  config.yaml  SOUL.md         │
  │  └── memory/  sessions/  skills/        │
  └─────────────────────────────────────────┘
                 │
                 ▼ Model provider API
       OpenRouter / Anthropic / OpenAI / Local
```

---

## Prerequisites

- **Server**: Coolify instance with SSH access
- **Local**: [Hermes Desktop](https://github.com/fathah/hermes-desktop/releases) installed
- **Key**: API key for your model provider (OpenRouter recommended)

---

## Step 1 — Initialize the data directory on the server

SSH into your Coolify server and run the init script once:

```bash
# Download and run the init script
curl -fsSL https://raw.githubusercontent.com/kcbdev/HERMES-AGENT-COOLIFY/main/init-hermes.sh | bash

# Or clone this repo and run locally:
chmod +x init-hermes.sh
./init-hermes.sh
```

The script:
1. Creates `/data/hermes` (or `$HERMES_DATA_PATH`)
2. Runs the Hermes setup wizard interactively
3. Writes `.env` and `config.yaml` to the data directory
4. Optionally injects `API_SERVER_KEY` for Hermes Desktop

> **Save the API_SERVER_KEY output.** You will need it in Step 3 (Hermes Desktop).

### Custom data path

```bash
HERMES_DATA_PATH=/data/my-agent ./init-hermes.sh
```

---

## Step 2 — Deploy in Coolify

### Option A — Git + Dockerfile (recommended)

1. In Coolify → **New Resource → Git Repository**
2. Repository URL: `https://github.com/kcbdev/HERMES-AGENT-COOLIFY`
3. Dockerfile path: `Dockerfile`
4. Branch: `main`

**Ports** (Coolify → Network tab):

| Container Port | Purpose |
|---|---|
| `8642` | Gateway API — Hermes Desktop connects here |
| `9119` | Web dashboard (optional) |

**Volume** (Coolify → Storages tab):

| Host Path | Container Path |
|---|---|
| `/data/hermes` | `/opt/data` |

**Environment Variables** (Coolify → Environment tab):

```env
# Volume ownership
HERMES_UID=1000
HERMES_GID=1000

# API server — REQUIRED for Hermes Desktop
API_SERVER_KEY=<paste the key from init script>
# (API_SERVER_HOST is hardcoded to 0.0.0.0 in docker-compose.coolify.yml)

# Model provider (fill ONE)
OPENROUTER_API_KEY=sk-or-v1-...
# ANTHROPIC_API_KEY=sk-ant-...
# OPENAI_API_KEY=sk-...
# OPENAI_BASE_URL=http://localhost:11434/v1   (for Ollama / local)
```

**Command override** (Coolify → General tab):
```
gateway run
```

**Domain** (Coolify → Domains tab):
- Add `agent.yourdomain.com` → port `8642` (for Hermes Desktop)
- Add `dashboard.yourdomain.com` → port `9119` (optional, for web UI)

Coolify's Caddy reverse proxy handles SSL automatically.

**Deploy** → click Deploy. First build takes ~5-10 minutes (installs Python deps + Playwright).

---

### Option B — Docker Compose

1. In Coolify → **New Resource → Docker Compose**
2. Paste the contents of `docker-compose.coolify.yml`
3. Set environment variables in Coolify's Environment tab (same as above)
4. Deploy

---

## Step 3 — Connect Hermes Desktop

### Install

Download from [github.com/fathah/hermes-desktop/releases](https://github.com/fathah/hermes-desktop/releases):

| Platform | File |
|---|---|
| macOS | `.dmg` |
| Linux | `.AppImage` or `.deb` |

**macOS — bypass Gatekeeper after install:**
```bash
xattr -cr "/Applications/Hermes Agent.app"
```

### Configure

In Hermes Desktop → **Settings → Gateway**:

| Field | Value |
|---|---|
| Gateway URL | `https://agent.yourdomain.com` |
| API Key | The `API_SERVER_KEY` from Step 1 |

Click **Connect** — the status dot turns green.

Open **Chat** and send a message. You should see a streamed response from your Coolify-hosted agent.

---

## Step 4 — Verify the deployment

```bash
# Health check
curl https://agent.yourdomain.com/health
# → {"status":"ok"}

# Authenticated API check
curl -H "Authorization: Bearer YOUR_API_SERVER_KEY" \
     https://agent.yourdomain.com/v1/models
# → {"object":"list","data":[...]}
```

---

## Multiple profiles

Each independent agent gets its own data directory, service, and port.

### Initialize a new profile

```bash
HERMES_DATA_PATH=/data/hermes-research ./init-hermes.sh
```

### Deploy the new profile in Coolify

Create a second service (Git or Docker Compose) with:
- Different service name: `hermes-research`
- Different volume: `/data/hermes-research` → `/opt/data`
- Different port mapping: `8643:8642`
- Different domain: `research.yourdomain.com`
- Different `API_SERVER_KEY`

### Add to Hermes Desktop

In Hermes Desktop → **Agents** → **Add Agent**:
- URL: `https://research.yourdomain.com`
- Key: the `API_SERVER_KEY` for this profile

Switch between agents from the Agents panel.

---

## SOUL.md — agent identity file

Drop a `SOUL.md` into the data directory to define your agent's identity.
The file is read at the start of every conversation.

```bash
cat > /data/hermes/SOUL.md << 'EOF'
# [Agent Name]

## Identity
You are [role]. [One-sentence purpose].

## Responsibilities
- [Task 1]
- [Task 2]

## Constraints
- Never [hard limit]
- Always [hard requirement]

## Working style
[Tone, output format preferences, escalation rules]
EOF
```

Edit it anytime — changes apply immediately on the next chat turn.

---

## Upgrading

To pull the latest hermes-agent version:

1. In Coolify → **[service] → Deployments → Redeploy** (triggers a fresh image build)
2. The build re-clones `main` from the upstream repo
3. Volume data is preserved

To pin to a specific version, set the `HERMES_REF` build arg in Coolify → Build tab:
```
HERMES_REF=v2026.5.16
```

---

## Backup

All agent state is in the host data directory. Back it up with:

```bash
# One-off
tar -czf hermes-backup-$(date +%Y%m%d).tar.gz /data/hermes

# Cron (daily at 3am, keep 14 days)
0 3 * * * tar -czf /backups/hermes-$(date +\%Y\%m\%d).tar.gz /data/hermes && \
          find /backups -name 'hermes-*.tar.gz' -mtime +14 -delete
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Container exits immediately | Missing `OPENROUTER_API_KEY` or bad `.env` | Check Coolify logs → Container |
| Health check returns 502 | Container still starting up | Wait 30s, retry |
| Hermes Desktop "connection refused" | `API_SERVER_KEY` mismatch or domain not resolving | Re-check Desktop settings and `curl /health` |
| Dashboard crashes | Dashboard subprocess not supervised | Restart service in Coolify |
| Permission errors in logs | `HERMES_UID`/`HERMES_GID` mismatch | `stat -c "%u %g" /data/hermes`, then set matching values in Coolify env |
| Playwright browser crashes | Not enough `/dev/shm` | Add `--shm-size=1g` in Coolify → Advanced → Docker Options |
| Build takes too long | Playwright installs ~300MB of Chromium | Expected on first build. Subsequent builds use Docker layer cache |
