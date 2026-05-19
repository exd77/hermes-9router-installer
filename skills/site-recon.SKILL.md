---
name: site-recon
description: Deep-dive reconnaissance on websites to discover what they are, their tech stack, backend architecture, API surface, features, social presence, and infrastructure. Use when asked to analyze, break down, investigate, recon, or check out a website or URL. Especially useful for finding early-stage or stealth crypto/DeFi/web3 projects. Triggers on phrases like "check out this site", "what is this site about", "break down this URL", "analyze this website", "recon this", "investigate this project".
---

# Site Recon

Systematic website reconnaissance to extract maximum intelligence from a URL.

## Process

Run all independent steps in parallel where possible to minimize latency.

### 1. First Contact (parallel)

Gather initial data simultaneously:

- **web_fetch** the URL (extract markdown, up to 15k chars)
- **browser open** the URL, resize to 1920x1080, screenshot
- **Evaluate** `document.documentElement.outerHTML.substring(0, 8000)` to get raw HTML/head tags

From the HTML head, extract: title, meta description, meta keywords, og tags, robots directives, framework hints.

### 2. Infrastructure Recon (parallel)

Run via exec in a single shell block:

```bash
# DNS
dig +short <domain> A
dig +short <domain> CNAME
dig +short www.<domain> CNAME
dig +short <domain> TXT
dig +short <domain> MX
dig +short <domain> NS

# IP geolocation
curl -s "https://ipinfo.io/<ip>/json"
```

Note the hosting provider (Vercel, Cloudflare, AWS, Hetzner, etc.), registrar (from NS records), and email setup.

### 3. Route Discovery (parallel)

Probe common paths in a single shell loop. Adapt the path list to the site's apparent type (crypto, DeFi, SaaS, etc.).

**Universal paths:**
```
/robots.txt /sitemap.xml /manifest.json /api /api/health /api/status
/docs /about /pricing /terms /privacy /blog /login /signup /register
/dashboard /app /settings
```

**Crypto/Trading paths:**
```
/trade /swap /portfolio /discover /tokens /markets /pairs /positions
/orders /watchlist /alerts /snipe /bot /copy-trade /terminal
/bridge /earn /airdrop /leaderboard /referral /pro /premium
```

**DeFi/Agent paths:**
```
/api/vaults /api/yields /api/strategies /api/agents
/llms.txt /llms-full.txt /agent-card /agent-card.json
/.well-known/agent.json /.well-known/ai-plugin.json
/.well-known/openapi.json /openapi.json /agents.txt
```

Only report paths that return non-404 status codes.

### 4. JS Bundle Analysis

Extract URLs, API endpoints, and service references from JavaScript chunks found in the HTML:

```bash
# For each JS chunk URL found in the HTML
curl -s "<chunk_url>" | grep -oP 'https?://[^"'\''\\s,\)\}]+' | sort -u
curl -s "<chunk_url>" | grep -oP 'wss?://[^"'\''\\s,\)\}]+' | sort -u
curl -s "<chunk_url>" | grep -oP '"/api/[^"]+' | sort -u
```

Search for domain-specific patterns:
- **Auth:** cognito, supabase, firebase, clerk, auth0, privy, dynamic
- **Data:** graphql, codex.io, birdeye, dexscreener, coingecko, defined.fi
- **Chains:** solana, ethereum, chainId, networkId, BSC, Base, Arbitrum
- **Wallets:** phantom, metamask, walletConnect, backpack, web3
- **Features:** quickBuy, snipe, swap, slippage, amountSol, leverage, copy
- **Social:** twitter.com, x.com, discord.gg, t.me, github.com

### 5. Live API Probing

For any discovered API endpoints (from route discovery or JS analysis):
- Hit health/status endpoints
- Try fetching public data (no auth)
- Check for OpenAPI specs
- Examine error responses for endpoint hints

### 6. External Intelligence (parallel)

```bash
# Web search for public presence
web_search: "<domain>" OR "<project name>"
web_search: "<project name>" crypto/DeFi/etc (based on apparent type)

# GitHub org/repos
curl -s "https://api.github.com/orgs/<name>/repos"

# Check social links found in JS/HTML
```

### 7. Content Files

Fetch any discovered machine-readable files:
- `/llms.txt`, `/llms-full.txt` — LLM integration docs
- `/agent-card.json` — agent capability card
- `/.well-known/agent.json` — A2A protocol
- `/agents.txt` — agent access policy
- `/robots.txt` — crawler policy
- `/openapi.json` — API spec

These often contain the most detailed technical information.

## Output Format

Structure the report as:

1. **What it is** — one-line summary
2. **Tech Stack** — frontend, backend, hosting, auth, data sources
3. **Features** — discovered functionality from routes, JS, and API probing
4. **Chains/Networks** — if crypto/DeFi related
5. **API Surface** — discovered endpoints, live data samples if available
6. **Infrastructure** — hosting, DNS, registrar, IP geolocation
7. **Social/Public Presence** — GitHub, Twitter, Discord, search results
8. **Interesting Findings** — anything notable: stealth mode, leaked keys, exposed APIs, unusual architecture, red/green flags
9. **Assessment** — stage (stealth/beta/production), sophistication level, comparable projects

Keep it dense and technical. Skip fluff.
