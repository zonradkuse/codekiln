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
| your skills, layers, allowlist and guideline profiles | `~/.config/codekiln/` |

It adds `~/.local/bin` to your `PATH` if it is missing; append
`-s -- --no-modify-path` after `bash` to skip that. To make the opinionated
coding guidelines the default for new projects (see
[Coding guidelines](#coding-guidelines)), append `-s -- --profile coding`.
Running it again updates the
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
codekiln open ~/code/app ts --profile coding  # with coding guidelines
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
| `codekiln init [dir] [layers...] [--profile <name\|none>]` | write or regenerate a project's config; run again with other layers or another profile to switch |
| `codekiln open [dir] [layers...] [--profile <name\|none>]` | init if needed, then open VS Code |
| `codekiln images` | list built images |
| `codekiln allow [hosts...]` | allow HTTPS to more hosts; without arguments, list yours |
| `codekiln disallow <hosts...>` | remove hosts you allowed |
| `codekiln profile [list]` | list guideline profiles, bundled and yours |
| `codekiln profile install <name> [--force]` | copy a bundled profile to yours |
| `codekiln profile new <name> [--from <profile>]` | start your own profile, empty or as a copy |
| `codekiln profile default [name\|none]` | show or set the profile new projects get |
| `codekiln profile show [name]` | print a profile |
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

## Allowing more hosts

```bash
codekiln allow api.example.com             # a host name
codekiln allow https://docs.example.com/x  # a pasted URL works too
codekiln allow 10.20.0.0/16                # an IPv4 address or network
codekiln allow                             # list your hosts
codekiln disallow api.example.com
```

Your hosts are kept in `~/.config/codekiln/network/allowlist.txt`, on top of
the bundled list, and you can edit that file by hand. The folder is mounted
read-only into every container, so a session can read the list but not change
it. `allow` and `disallow` re-apply the firewall in every running codekiln
container straight away; there is nothing to rebuild. After editing the file
by hand, run `sudo /usr/local/sbin/egress-firewall` in the container, or
restart it.

Only HTTPS on port 443 is allowed, and only exact host names: no wildcards,
since the firewall works on the addresses a name resolves to. List each
subdomain you need. Projects set up before this feature need
`codekiln init` (or `codekiln open`, which does it for you) and "Rebuild
Container", and the image needs one `codekiln rebuild`.

## Coding guidelines

codekiln is not tied to coding, so projects get no coding rules unless you
choose a profile. A profile is a folder with one `AGENTS.md`, and each
project picks one:

```bash
codekiln init ~/code/app --profile coding    # opinionated coding guidelines
codekiln init ~/code/notes --profile none    # none for this project
codekiln profile default coding              # what new projects get without --profile
```

The first use of a bundled profile copies it, for example
[`profiles/coding/AGENTS.md`](profiles/coding/AGENTS.md), to
`~/.config/codekiln/profiles/coding/AGENTS.md`. That copy is yours: edit it to
your own guidelines, and keep the folder in git if you like. Updates never
overwrite it, and `profile install coding --force` refreshes it from the
bundled version, keeping yours as `AGENTS.md.bak`.

For a project that needs different rules, make your own profile:

```bash
codekiln profile new firmware --from coding  # or without --from for an empty one
$EDITOR ~/.config/codekiln/profiles/firmware/AGENTS.md
codekiln init ~/code/firmware --profile firmware
```

The project's choice is stored in its generated `devcontainer.json`.
Re-running `init` without `--profile` keeps it, and changing the default
doesn't affect existing projects. After switching, use "Rebuild Container".
Edits to a profile's `AGENTS.md` show up in new sessions without a rebuild.

The chosen profile is mounted read-only at `/etc/codekiln/guidelines/`. The
file is plain `AGENTS.md`, so it is not tied to one harness:

- **Claude Code** gets it through an `@import` at the end of the managed
  rules (`image/agent-rules.md`), from new sessions on. Run `/memory` in a
  container to confirm that `/etc/codekiln/guidelines/AGENTS.md` is listed.
- **Other harnesses** can point their global instructions file at the same
  path.

Nothing is written into your projects. A project's own `AGENTS.md` or
`CLAUDE.md` still loads, and the guidelines tell the agent to follow the
project's instructions where the two disagree. The sandbox rules still come
first.

## SELinux

With SELinux enforcing (Fedora, RHEL), Docker and Podman don't let a
container read host folders unless they carry the `container_file_t` label.
`codekiln init` and `codekiln open` therefore relabel codekiln's own mounted
folders (skills, network and profiles under `~/.config/codekiln`, or your
`CODEKILN_SKILLS` folder) with `chcon -R -t container_file_t`. Nothing else is
touched. New files in those folders inherit the label; a file moved in from
elsewhere keeps its old one until the next `open`. A full `restorecon` resets
the labels, and the next `open` sets them again. On hosts without SELinux
this step does nothing.

## What is restricted

**Telemetry.** Claude Code's opt-out variables are set in the image and again
in managed settings, which project and user settings cannot override. Side
effect: features that rely on feature-flag fetching, such as Remote Control,
are unavailable.

**Network.** `image/egress-firewall.sh` rejects all outbound traffic except DNS
and HTTPS to the hosts in `image/egress-allowlist.txt`: Anthropic's API and
login hosts, public git hosting, and the common public package registries.
Add your own with `codekiln allow` (see [Allowing more hosts](#allowing-more-hosts)).
If a host stops responding in a long-running container, refresh the resolved
addresses with `sudo /usr/local/sbin/egress-firewall`.

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
