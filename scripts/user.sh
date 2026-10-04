#!/usr/bin/env bash
# Personal setup for a coderbox. Run as your normal user (not root). Safe to re-run.

set -euo pipefail

GIT_NAME="${GIT_NAME:-Vipul V Patil}"
GIT_EMAIL="${GIT_EMAIL:-vipulvpatil@gmail.com}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run as your normal user, not root"

log "Node (via nvm, current LTS)"
export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  NVM_VERSION="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r .tag_name)"
  # PROFILE=/dev/null: don't let nvm edit ~/.bashrc; config/bashrc loads it.
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | PROFILE=/dev/null bash
fi
set +u   # nvm is not compatible with `set -u`
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
set -u

log "Claude Code"
if ! command -v claude >/dev/null && [[ ! -x "$HOME/.local/bin/claude" ]]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

log "code-server extension and settings"
if command -v code-server >/dev/null; then
  code-server --install-extension anthropic.claude-code
  settings="$HOME/.local/share/code-server/User/settings.json"
  if [[ ! -f "$settings" ]]; then   # never overwrite settings you changed
    mkdir -p "$(dirname "$settings")"
    cp "$REPO_DIR/config/code-server-settings.json" "$settings"
  fi
else
  echo "code-server not installed; skipping (run system.sh first)"
fi

log "Shell config"
mkdir -p "$HOME/.config/coderbox"
cp "$REPO_DIR/config/bashrc" "$HOME/.config/coderbox/bashrc"
# shellcheck disable=SC2016  # $HOME must stay literal in ~/.bashrc
hook='[ -f "$HOME/.config/coderbox/bashrc" ] && . "$HOME/.config/coderbox/bashrc"'
grep -qxF "$hook" "$HOME/.bashrc" 2>/dev/null || printf '\n%s\n' "$hook" >> "$HOME/.bashrc"

log "Git"
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global core.editor vim
git config --global init.defaultBranch main

mkdir -p "$HOME/labs"

log "Done"
echo "Next steps: docs/after-first-boot.md"
