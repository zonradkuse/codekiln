# codekiln

Sandboxed dev containers for coding agents: an egress allowlist, stackable
language layers, and one folder of skills shared by every project.

It currently targets Claude Code in VS Code. Telemetry is switched off,
outbound network access is limited to an allowlist, and default rules stop the
agent from pushing or publishing. The configuration lives in your home
directory and is added to a project on demand, so nothing has to be committed
to the projects you work on.

> **Attribution.** The overall approach (Claude Code in a dev container behind
> an in-container egress allowlist, with state kept in a named volume) follows
> the reference dev container that Anthropic publishes in the
> [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/.devcontainer)
> repository and describes in the
> [Claude Code dev container docs](https://code.claude.com/docs/en/devcontainer).
> The files here were written separately and are organised differently.
> This project is not affiliated with or endorsed by Anthropic.

## Requirements

- Docker
- VS Code with the Dev Containers extension
- bash and git (Linux, macOS or WSL)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zonradkuse/codekiln/main/install.sh | bash
```

This installs for your user only, without sudo:

| What | Where |
|---|---|
| program (a git clone) | `~/.local/share/codekiln` |
| command | `~/.local/bin/codekiln` (symlink) |
| your skills and layers | `~/.config/codekiln/` |

It adds `~/.local/bin` to your `PATH` if it is missing; append
`-s -- --no-modify-path` after `bash` to skip that. Running it again updates the
install, as does `codekiln update`. If you would rather read the script first,
clone the repository and run `./install.sh` from the checkout.

If you don't want to run random bash scripts from the internet, you can do those steps
manually. Clone the repository into the place of your choice, run `install.sh` or set
customize the setup. Make sure to add `bin/codekiln` to your `PATH`.

Then build the base image:

```bash
codekiln build
```

Add this to your VS Code user settings. The container cannot reach the
extension marketplace, so the host has to download extensions for it:

```json
"remote.downloadExtensionsLocally": true
```

## Use

```bash
codekiln open ~/code/some-project          # base image
codekiln open ~/code/firmware cpp arm-none # base + layers
```

This writes `.devcontainer/devcontainer.json` into the project, hides it from
git through `.git/info/exclude`, and opens VS Code. Choose "Reopen in
Container", run `claude`, and log in once. The login is kept in a Docker volume
shared by all projects.

| Command | What it does |
|---|---|
| `codekiln layers` | list the available language layers |
| `codekiln build [layers...]` | build the base image and one image with the layers stacked on it |
| `codekiln rebuild` | rebuild the base and every stack you have built |
| `codekiln init [dir] [layers...]` | write or regenerate a project's config; run again with other layers to switch |
| `codekiln open [dir] [layers...]` | init if needed, then open VS Code |
| `codekiln images` | list built images |
| `codekiln update` | pull the latest codekiln |
| `codekiln paths` | show where codekiln keeps its files |

Docker build options such as `--no-cache` can be added to `build` and `rebuild`.
Claude Code does not auto-update inside the container; rebuild to update it.

## Language layers

| Layer | Adds |
|---|---|
| `cpp` | clang as default compiler, lld, lldb, clangd, clang-format, clang-tidy, CMake, Ninja, ccache |
| `arm` | cross compilers for ARM Linux (64-bit and 32-bit hard-float) |
| `arm-none` | bare-metal ARM toolchain with newlib |
| `mingw` | mingw-w64 for 64-bit and 32-bit Windows |
| `python` | ruff, a uv-managed CPython, headers for native wheels |
| `ts` | Angular CLI and TypeScript |

The base image already contains Python 3, uv, poetry, and Node.js (latest LTS
through nvm).

A layer is a short script with two functions: `as_root` for system packages
and `as_user` for per-user tools. To add your own, put a script in
`~/.config/codekiln/layers/`; one with the same name as a bundled layer
replaces it.

```bash
# ~/.config/codekiln/layers/rust.sh
# Rust toolchain via rustup
as_root() { apt-get update; apt-get install -y --no-install-recommends build-essential; }
as_user() { curl -fsSL https://sh.rustup.rs | sh -s -- -y; }
```

## Shared skills

Put skills in `~/.config/codekiln/skills/<name>/SKILL.md`. The folder is
mounted read-only into every container as Claude Code's managed skills
location, so the skills load in every project and a session cannot modify them.

- A new session picks up changes; in a running session use `/reload-skills`.
- A shared skill wins over a project skill with the same name.
- Keep the folder in its own git repository if you want history.
- Set `CODEKILN_SKILLS` to use a different host folder.

## What is restricted

**Telemetry.** Claude Code's opt-out variables are set in the image and again
in managed settings, which project and user settings cannot override. Side
effect: features that rely on feature-flag fetching, such as Remote Control,
are unavailable.

**Network.** `image/egress-firewall.sh` rejects all outbound traffic except DNS
and HTTPS to the hosts in `image/egress-allowlist.txt`: Anthropic's API and
login hosts, public git hosting, and the common public package registries.
Edit the list and rebuild to change it. If a host stops responding in a
long-running container, refresh the resolved addresses with
`sudo /usr/local/sbin/egress-firewall`.

**Rules for the agent.** `image/agent-rules.md` is installed as managed policy
and tells Claude never to push or publish. `image/managed-settings.json` denies
the matching commands, and the image rewrites git push URLs to an unresolvable
host. The last one also blocks your own pushes from inside the container; push
from the host, or remove that block from `image/Dockerfile`.

## Limits

This reduces what a session can reach. It is not a hard security boundary.

- The allowlist works on IP addresses resolved at container start. Other sites
  that share a CDN address with an allowed host are reachable, and DNS remains
  a possible exfiltration channel.
- Telemetry and inference use the same Anthropic host, so the telemetry opt-out
  relies on Claude Code honouring its settings, not on the firewall.
- The deny rules match command text. They catch the usual forms, not every
  possible wrapper.
- Package registries are reachable, so install scripts from any package run
  inside the container. Keep credentials out of it.
- VS Code can share host git credentials with dev containers. The push rewrite
  covers that case; removing it re-opens it.
- `apt` does not work at runtime. Add system packages to a layer.
