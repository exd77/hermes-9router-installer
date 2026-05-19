# hermes-9router-installer

A one-command bash installer that sets up [Hermes Agent](https://hermes-agent.nousresearch.com/) and [9Router](https://github.com/decolua/9router) on the same Linux box, wires the Hermes messaging gateway to a Telegram bot, drops 9Router into the background, and prints the public dashboard URL when it's done.

Tested on Ubuntu 22.04 / 24.04 (AWS, Hetzner, bare VPS). Works on any Linux with `apt-get`, `node`, `npm`, `python3`, and `systemd --user`.

## Quickstart

```bash
# 1. Clone & enter
git clone https://github.com/exd77/hermes-9router-installer.git
cd hermes-9router-installer

# 2. Run the installer (default = full install)
chmod +x install.sh
./install.sh
```

That's it. The script will:

1. Install Hermes Agent from the official `install.sh`.
2. Install the Hermes systemd gateway service (`hermes gateway install`).
3. Drop you into `hermes gateway setup` so you can paste your Telegram bot token from @BotFather.
4. Run `sudo npm i -g 9router`.
5. Start 9Router and Hide it to tray (Background) — on a headless VPS this means a `systemd --user` service that auto-restarts and survives reboot.
6. Install any skills from the `skills/` folder into `~/.hermes/skills/`.
7. Print your public dashboard URL like `http://<VPS_IP>:20128/dashboard`.

## Commands

```bash
./install.sh                # default — full install
./install.sh install        # same as above
./install.sh start          # start 9Router background service
./install.sh stop           # stop it
./install.sh restart        # restart it
./install.sh status         # systemd status
./install.sh logs           # tail -f logs
./install.sh dashboard      # print public + local dashboard URL
./install.sh skills         # (re)install skills from ./skills/ into ~/.hermes/skills/
./install.sh uninstall      # remove 9router service/tray helper files (keeps Hermes + npm package)
```

After install, two helper commands also land in `~/.local/bin/`:

```bash
9router-tray         # run 9router and Hide to tray (Background)
9router-dashboard    # open or print the dashboard URL
```

## Environment variables

Set these before running `./install.sh` to override defaults:

```
NINE_ROUTER_PORT=20128                       # 9Router HTTP port
NINE_ROUTER_HOST=0.0.0.0                     # bind interface (0.0.0.0 = public)
NINE_ROUTER_BASE_URL=http://localhost:20128  # used in env files / printed URLs
HERMES_HOME=$HOME/.hermes                    # Hermes data dir
HERMES_INSTALL_URL=https://hermes-agent.nousresearch.com/install.sh
SKILLS_SRC_DIR=$(pwd)/skills                 # where to read SKILL.md files from
```

Example — install on a non-default port:

```bash
NINE_ROUTER_PORT=20200 NINE_ROUTER_BASE_URL=http://localhost:20200 ./install.sh
```

## How it works

1. **Tooling check.** `curl`, `git`, `node`, `npm`, `python3` — auto-installs the missing ones via `apt-get` if needed.
2. **Hermes install.** Pipes the official Hermes installer with `--skip-setup` so we control the flow ourselves. Falls back to symlinking `~/.hermes/hermes-agent/venv/bin/hermes` into `~/.local/bin` if `hermes` isn't on PATH yet.
3. **Hermes gateway install.** Calls `hermes gateway install` to lay down the systemd/launchd service for the messaging gateway.
4. **Hermes gateway setup (interactive).** Prints a green panel with instructions, then hands stdin straight to `hermes gateway setup` so you can paste your Telegram bot token + chat ID. After it returns, the script runs `hermes gateway restart` + `hermes gateway status` so the new token is live.
5. **9Router install.** Runs `sudo npm i -g 9router` (or plain `npm i -g 9router` if `sudo` isn't available).
6. **Helpers.** Writes `9router-bg`, `9router-dashboard`, and `9router-tray` to `~/.local/bin/`.
7. **Background service.** Writes `~/.config/systemd/user/9router.service` with `Restart=always`, runs `loginctl enable-linger` so it survives logout, and writes a desktop autostart `.desktop` for graphical sessions.
8. **Hide to tray (Background).** `9router-tray` picks the best mode for the host: real tray icon via `kdocker`/`alltray` if a desktop session is present, otherwise `systemctl --user start 9router.service`, with `nohup` as the last fallback.
9. **Skills install.** Reads `skills/*.md`, parses `name:` from the YAML frontmatter, slugs it, and copies each file to `~/.hermes/skills/<slug>/SKILL.md`.
10. **Public URL.** Detects the VPS public IP (api.ipify.org → ifconfig.me → ipinfo.io → icanhazip.com → `hostname -I`) and prints the dashboard + API endpoints in a green panel.

## File layout

```
hermes-9router-installer/
├─ install.sh        # the installer
├─ skills/           # SKILL.md files that get copied to ~/.hermes/skills/
│  └─ site-recon.SKILL.md
└─ README.md
```

Files generated at runtime (not in this repo):

- `~/.hermes/` — Hermes config, profiles, gateway state.
- `~/.hermes/skills/<slug>/SKILL.md` — skills installed from `./skills/`.
- `~/.hermes/9router-gateway.env` — convenience env file pointing at the 9Router OpenAI-compatible endpoint.
- `~/.local/bin/9router-bg`, `9router-dashboard`, `9router-tray` — helper commands.
- `~/.config/systemd/user/9router.service` — the background service unit.
- `~/.config/autostart/9router-background.desktop` — desktop autostart entry (only matters on graphical sessions).

## Notes

- On AWS / Hetzner / any cloud VPS, open inbound TCP `20128` in the security group / firewall before sharing the public dashboard URL. The script binds 9Router to `0.0.0.0` by default.
- `hermes gateway setup` needs an interactive TTY. If you ever pipe the installer (`curl ... | bash`), the gateway setup step prints a warning and tells you to run `hermes gateway setup` manually afterwards — nothing else hangs.
- Skill files must have YAML frontmatter with at least a `name:` line. Drop more `*.md` files into `skills/` and run `./install.sh skills` to push them into Hermes without touching anything else.
- `./install.sh uninstall` only removes the 9Router service/tray helper files. Hermes itself stays installed because it has its own uninstall path (`hermes gateway uninstall`, plus removing `~/.hermes/hermes-agent`).
- Sources: Hermes Agent — <https://hermes-agent.nousresearch.com/>. 9Router — <https://github.com/decolua/9router>.
