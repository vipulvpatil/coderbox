# After first boot

Do these once, right after the server is created.

**Where to type the commands:** open code-server in your browser, then open its
terminal from the menu: **☰ → Terminal → New Terminal** (shortcut: Ctrl + backtick).
The terminal already runs as your `coder` user, so type the commands as shown, without `sudo`.

## 1. Check the setup finished

```bash
cloud-init status --wait
```

It should print `status: done`. If it says `error`, see [Troubleshooting](#troubleshooting).

Then load the new shell config into this terminal:

```bash
source ~/.bashrc
```

## 2. Log in to GitHub

```bash
gh auth login
```

Choose: **GitHub.com** → **HTTPS** → **Yes** (authenticate Git) → **Login with a web
browser**. Open the link it shows and enter the code.

Check it worked:

```bash
gh auth status
```

## 3. Log in to Claude Code

```bash
claude
```

Follow the login prompt, then exit with `/exit`. The Claude Code panel in code-server
uses the same login.

## 4. Clone your projects

```bash
cd ~/labs
gh repo clone vipulvpatil/<repo>
```

## 5. Check everything

```bash
node -v && go version && gh --version | head -1 && claude --version
```

## Optional: SSH from another device

Tailscale SSH is on, so from any of your Tailscale devices:

```bash
ssh coder@<server-name>
```

No SSH key needed: Tailscale checks who you are. Tailscale may ask you to confirm in a
browser the first time.

---

## Troubleshooting

**See what the setup did.** Everything the scripts printed is in:

```bash
sudo less /var/log/cloud-init-output.log
```

**Re-run the setup.** Both scripts are safe to re-run. Run them as a background job so
they survive your terminal disconnecting (setup may restart Tailscale or code-server):

```bash
sudo systemd-run --unit=coderbox-setup --collect bash -c \
  '/opt/coderbox/scripts/system.sh && sudo -iu coder /opt/coderbox/scripts/user.sh'
journalctl -fu coderbox-setup        # watch it; Ctrl+C stops watching, not the setup
```

**The page doesn't load.**

```bash
tailscale status                         # is this device on the tailnet?
systemctl status code-server@coder       # is code-server running?
systemctl status caddy                   # is Caddy running?
sudo journalctl -u caddy -n 50           # certificate errors show up here
```

A certificate error usually means *HTTPS Certificates* is off in the
[Tailscale DNS settings](https://login.tailscale.com/admin/dns). Turn it on, then
`sudo systemctl restart caddy`.

**The server never appears in Tailscale.** The auth key was wrong, expired, or already
used. Open the server's **Console** in Hetzner, log in as root, then:

```bash
sudo tailscale up --ssh                  # prints a login link instead of using a key
```

Then re-run the setup as above.

**Locked out completely.** There are no public ports, so the Hetzner web **Console** is the
way in. If you don't know the root password, use *Rescue → Reset root password* in Hetzner
first.
