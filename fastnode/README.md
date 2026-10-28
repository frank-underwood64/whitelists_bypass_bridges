# FastNode

```
███████╗ █████╗ ███████╗████████╗███╗   ██╗ ██████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔════╝╚══██╔══╝████╗  ██║██╔═══██╗██╔══██╗██╔════╝
█████╗  ███████║███████╗   ██║   ██╔██╗ ██║██║   ██║██║  ██║█████╗
██╔══╝  ██╔══██║╚════██║   ██║   ██║╚██╗██║██║   ██║██║  ██║██╔══╝
██║     ██║  ██║███████║   ██║   ██║ ╚████║╚██████╔╝██████╔╝███████╗
╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝
  Remnawave node toolkit  ·  v1.0.0                  by @underwood642
```

One bash script, with an interactive menu and a CLI, that prepares a fresh Ubuntu/Debian VPS for a
[Remnawave](https://docs.rw/) node: BBR and kernel tuning, Docker, firewall, a **self-steal** site with a real
Let's Encrypt certificate, the node's compose file, and a `doctor` command that tells you why a node is slow.

[Русская версия](README.ru.md)

## What it does

| Step | What happens |
|---|---|
| **Tuning** | BBR + `fq`, sane TCP buffers/queues/keepalive, `nofile=1048576` (system, systemd and Docker). Verifies the values actually applied and names the file that overrides them if not |
| **Docker** | Official Docker Engine + compose plugin, log rotation, `nofile` ulimit |
| **Firewall** | `ufw`: SSH (detected, never locked out), 80, 443, and the node port **only for the panel IP**. Refuses to enable `ufw` if it would cut other public services, unless you say so |
| **Self-steal** | nginx on `127.0.0.1:8443` with a real certificate for your domain, so Reality's `dest` is your own site. The stub page is **generated per install** (4 templates, random name, colour, favicon), so nodes do not share one fingerprint. Bring your own site with `--site-dir` |
| **Node** | `/opt/remnanode` compose (`network_mode: host`, ulimits) and `.env`; or use the compose file copied from the panel with `--compose-file` |
| **Doctor** | ~30 checks: BBR, sysctl drift, container limits, clock sync, ports, firewall, dest TLS 1.3/h2/X25519, certificate age, Reality fallback, IPv4/IPv6 egress, DNS latency, MTU, TCP retransmits |

Everything is idempotent: run it again any time. Overwritten files are backed up to `/var/backups/fastnode/<timestamp>/`.

## Quick start

1. Create an **A record** for your domain pointing at the server (*DNS only*, not proxied by Cloudflare).
2. If your host has an external firewall / security group, open **80** and **443** there.
3. Create the node in the Remnawave panel and copy its `SECRET_KEY`.

```bash
curl -fsSL https://raw.githubusercontent.com/frank-underwood64/whitelists_bypass_bridges/main/fastnode/fastnode.sh -o fastnode.sh
less fastnode.sh              # it runs as root, read it first
sudo bash fastnode.sh         # opens the menu
```

Non-interactive:

```bash
echo 'PASTE_SECRET_KEY' > /root/node.key && chmod 600 /root/node.key
sudo bash fastnode.sh install \
  --domain node1.example.com --email you@example.com \
  --panel-ip 203.0.113.5 --secret-key-file /root/node.key
```

See what would happen without changing anything: add `--dry-run`.

## Commands

```
fastnode                 interactive menu
fastnode install         full setup
fastnode tune            BBR + sysctl + limits
fastnode docker          Docker + compose
fastnode firewall        ufw rules
fastnode selfsteal       nginx + certificate + stub site
fastnode node            compose/.env + start the node
fastnode doctor          diagnostics (exit code 1 if something failed)
fastnode status          what is installed
fastnode logs            the log, colours stripped (attach it to issues)
```

`fastnode --help` lists every option. The script installs itself as `/usr/local/bin/fastnode` after `install`.
The interface language follows `$LANG` (Russian or English); switch it in the menu (`L`) or with `--lang ru|en`.

## After the script: the panel side

```jsonc
// Config Profile -> Reality inbound (port 443)
"dest": "127.0.0.1:8443",
"serverNames": ["node1.example.com"],
"xver": 0
// privateKey / shortIds: your own (xray x25519, openssl rand -hex 8)
```

* **Host** of this node: `sni = node1.example.com`.
* **Node**: address = server IP, port = `2222` (or your `--node-port`).
* Then `fastnode doctor`. The *Reality fallback* check confirms that strangers on `:443` get your stub site.

## Status

v1.0.0. Exercised on Ubuntu 24.04: the interactive menu and wizard (real pty), `doctor`, `--dry-run`, option validation,
and the whole self-steal path (generated sites, nginx config, TLS 1.3 / h2 / X25519 on the loopback dest,
idempotent re-runs, backups). The tuning, firewall and Docker-install steps reuse the logic of an earlier script that ran
on production servers, but have not been re-run end to end in this version. Please report anything odd.

## Platforms

| OS | Status |
|---|---|
| Ubuntu 24.04 LTS and newer, Debian 12 and newer | supported; 24.04 is the reference platform |
| Older Ubuntu / Debian | runs with a warning |
| Other apt-based distributions | runs with a warning (untested) |
| Without `apt` / systemd | refused unless `--force-os` |

Containers (LXC/OpenVZ) share the host kernel: sysctl tuning, including BBR, may not apply there. The script and `doctor` tell you.

## Safety and transparency

* **Files it writes:** `/etc/sysctl.d/99-zz-fastnode.conf`, `/etc/modules-load.d/fastnode-bbr.conf`,
  `/etc/security/limits.d/99-fastnode.conf`, `/etc/systemd/system.conf.d/99-fastnode.conf`,
  `/etc/docker/daemon.json` (only if absent), `ufw` rules (commented `FastNode: ...`),
  `/etc/nginx/sites-available/fastnode`, `/var/www/fastnode`, `/opt/remnanode/*`,
  `/etc/fastnode/fastnode.conf` (settings only, **no secrets**), `/var/log/fastnode.log`.
* **It does not touch** your SSH configuration, users, other nginx sites, or an existing `daemon.json`.
* **Secrets:** `SECRET_KEY` is taken from a file, the `FASTNODE_SECRET_KEY` variable or a hidden prompt, and is written only to `/opt/remnanode/.env` (mode 600). `--secret-key` works but warns: it lands in shell history.
* **Network calls:** apt, `get.docker.com`, Let's Encrypt, `api.ipify.org` / `ifconfig.me` (public IP), `1.1.1.1` (DNS check). `doctor` also pings `1.1.1.1` and calls `api64.ipify.org`.
* It changes firewall, kernel and network settings on the machine you run it on. Use it on servers you own, within your provider's terms and your local law. Read the [license](LICENSE): no warranty.

## Contributing

Open an issue with the output of `fastnode doctor` and `fastnode logs`. Pull requests are welcome; CI runs `shellcheck`.

## License

[MIT](LICENSE) © 2026 @underwood642
