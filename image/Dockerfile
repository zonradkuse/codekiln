# Claude Code dev container: telemetry off, default-deny egress firewall.
# Base image. Build with: codekiln build   (tags codekiln:base)
FROM ubuntu:26.04

# Version number or release channel (latest | stable) for the native installer.
ARG CLAUDE_CODE_VERSION=latest
ARG DEBIAN_FRONTEND=noninteractive
ARG NVM_VERSION=0.40.3
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less procps sudo iptables ipset mawk xz-utils libatomic1 \
      python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# uv (Python package/project manager), copied from the official image.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# --- Telemetry / non-essential traffic off -----------------------------------
# Set both as process env and in managed settings (highest precedence, so no
# user or project settings file can switch it back on).
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_FEEDBACK_COMMAND=1 \
    CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1 \
    DISABLE_AUTOUPDATER=1 \
    DO_NOT_TRACK=1 \
    CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1 \
    ENABLE_CLAUDEAI_MCP_SERVERS=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false
COPY managed-settings.json /etc/claude-code/managed-settings.json

# --- Default rules for Claude ---------------------------------------------------
# agent-rules.md becomes the managed-policy CLAUDE.md: loaded in every session,
# in every project. (It has another name in this repo so that Claude Code does
# not apply it when someone works on the repo itself.)
COPY agent-rules.md /etc/claude-code/CLAUDE.md

# Shared skills: the host folder ~/.config/codekiln/skills is bind-mounted
# here read-only (see devcontainer.json). This is Claude Code's managed skills
# location, so the skills load in every project.
RUN mkdir -p /etc/claude-code/.claude/skills

# Your own allowlist (~/.config/codekiln/network) is bind-mounted here
# read-only; the firewall reads /etc/codekiln/user/allowlist.txt if present.
RUN mkdir -p /etc/codekiln/user

# Backstop for "never push": rewrite every push URL to an unresolvable host.
# Fetch/clone are unaffected. This also stops pushes from the VS Code UI and the
# container terminal - push from the host. Delete this block to allow pushing.
RUN git config --system url."https://push-disabled.invalid/".pushInsteadOf "https://" \
    && git config --system --add url."https://push-disabled.invalid/".pushInsteadOf "ssh://" \
    && git config --system --add url."https://push-disabled.invalid/".pushInsteadOf "git@"

# --- Egress firewall ------------------------------------------------------------
# Script, allowlist and sudo rule are root-owned. The "ubuntu" user may run this
# one script through sudo and nothing else, so a session cannot alter the rules.
COPY --chmod=0755 egress-firewall.sh  /usr/local/sbin/egress-firewall
COPY --chmod=0644 egress-allowlist.txt /etc/codekiln/egress-allowlist.txt
COPY --chmod=0440 sudoers-egress      /etc/sudoers.d/codekiln-egress
RUN chmod 0644 /etc/claude-code/managed-settings.json /etc/claude-code/CLAUDE.md

# --- Persistent Claude state (login, settings, history) ------------------------
# ~/.claude.json normally lives outside ~/.claude; CLAUDE_CONFIG_DIR moves it
# inside so one volume mount keeps you logged in across rebuilds.
RUN mkdir -p /home/ubuntu/.claude && chown ubuntu:ubuntu /home/ubuntu/.claude
ENV CLAUDE_CONFIG_DIR=/home/ubuntu/.claude

# --- Claude Code (native installer, no Node.js needed) -------------------------
# Installs to ~/.local/bin/claude. Auto-update is disabled above: rebuild with
# `codekiln build --no-cache` to update.
USER ubuntu
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

# --- Node.js via nvm (latest LTS at build time) ---------------------------------
# NVM_SYMLINK_CURRENT keeps ~/.nvm/current pointing at the active version, so
# node/npm are on PATH in non-interactive shells too (Claude's Bash tool, VS Code
# tasks), not only where ~/.bashrc has loaded nvm.
# Do not set NPM_CONFIG_PREFIX: nvm refuses to run with it. `npm install -g`
# already lands in the user-owned nvm directory.
ENV NVM_DIR=/home/ubuntu/.nvm \
    NVM_SYMLINK_CURRENT=true
RUN curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash \
    && . "$NVM_DIR/nvm.sh" --no-use \
    ; nvm install --lts \
    && nvm alias default 'lts/*' \
    && nvm use default \
    && node --version && npm --version \
    && nvm cache clear

# --- Python tooling: poetry (uv is installed system-wide above) -------------------
RUN uv tool install poetry && uv cache clean

# ~/.local/bin: claude, poetry and other uv tools. ~/.nvm/current/bin: node, npm.
ENV PATH=/home/ubuntu/.local/bin:/home/ubuntu/.nvm/current/bin:$PATH
RUN claude --version && node --version && uv --version && poetry --version
