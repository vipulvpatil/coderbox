# coderbox

My personal cloud dev box: VS Code in the browser (code-server) on a Hetzner
server, reachable **only over my Tailscale network**. No public ports.

```
iPad / laptop ──Tailscale──▶ coderbox
                              ├─ https://<name>.<tailnet>.ts.net → code-server
                              └─ SSH (Tailscale SSH)
```

## What you get

- code-server with HTTPS (Caddy + a Tailscale certificate)
- Node (via nvm), Go, Claude Code, GitHub CLI, git, build tools
- A `coder` user with sudo, no password logins anywhere
- Firewall: nothing reachable from the internet

## Create a new server

**Once per tailnet:** in the [Tailscale DNS settings](https://login.tailscale.com/admin/dns),
make sure *MagicDNS* and *HTTPS Certificates* are on.

1. **Get a Tailscale auth key.** [Tailscale → Settings → Keys](https://login.tailscale.com/admin/settings/keys)
   → *Generate auth key*. Leave *Reusable* **off**, set expiry to **1 day**.
2. **Fill in the cloud config.** Copy [`cloud-init.yaml`](cloud-init.yaml) and replace
   `tskey-auth-PASTE-YOUR-KEY-HERE` with your key. Don't commit it.
3. **Create the server on Hetzner.** Image: **Ubuntu 24.04**. Paste the file into
   *Cloud config*. Give it the name you want to see in Tailscale (e.g. `coderbox`).
4. **Wait ~5 minutes**, until the server shows up in your
   [Tailscale machines](https://login.tailscale.com/admin/machines).
5. **Open** `https://<server-name>.<your-tailnet>.ts.net` in a browser on any of your
   Tailscale devices. The first load can take a minute while the certificate is issued.
6. **Finish setup** (log in to GitHub and Claude): [docs/after-first-boot.md](docs/after-first-boot.md).

Something wrong? See [docs/after-first-boot.md#troubleshooting](docs/after-first-boot.md#troubleshooting).

## Update an existing server

The scripts are safe to re-run. From a terminal on the server:

```bash
cd /opt/coderbox && sudo git fetch --depth 1 origin tag v1.3 && sudo git checkout v1.3   # the tag you want
sudo systemd-run --unit=coderbox-setup --collect bash -c \
  '/opt/coderbox/scripts/system.sh && sudo -iu coder /opt/coderbox/scripts/user.sh'
journalctl -fu coderbox-setup        # watch it; Ctrl+C stops watching, not the setup
```

`systemd-run` runs the setup as its own background job, so it keeps going even if your
terminal disconnects (setup may briefly restart Tailscale and code-server).

## What's in this repo

| File | What it does |
|---|---|
| `cloud-init.yaml` | Hetzner boot config. Clones this repo and runs the two scripts. |
| `scripts/system.sh` | Runs as root: user, firewall, SSH, Tailscale, Go, gh, code-server, Caddy. |
| `scripts/user.sh` | Runs as `coder`: Node, Claude Code, editor settings, shell aliases, git. |
| `config/` | Shell config and code-server settings copied by `user.sh`. |
| `docs/after-first-boot.md` | The manual steps, and troubleshooting. |

`cloud-init.yaml` pins a release tag (`--branch v1`). After changing the scripts and
testing them, tag a new release and update that line.

## Safe to be public

Nothing secret lives here. The only secret is the Tailscale auth key, which goes in
your copy of `cloud-init.yaml` and is single-use and short-lived. The server
deletes its copy after joining the tailnet.
