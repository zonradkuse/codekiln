#!/usr/bin/env bash
# codekiln installer. Typical use:
#
#   curl -fsSL https://raw.githubusercontent.com/zonradkuse/codekiln/main/install.sh | bash
#
# Installs for the current user only, no sudo:
#   program  -> ~/.local/share/codekiln   (a git clone; update with `codekiln update`)
#   command  -> ~/.local/bin/codekiln     (symlink)
#   your own -> ~/.config/codekiln/       (skills/, layers/, network/, profiles/;
#                                          never touched by updates)
#
# Options:      --no-modify-path   do not add ~/.local/bin to PATH in your shell profile
#               --profile <name>   install a guidelines profile and make it the default
#                                  for new projects, e.g. --profile supervised-coding
#                                  (same as `codekiln profile default <name>` later)
#               (with curl:  ... | bash -s -- --no-modify-path --profile supervised-coding)
# Environment:  CODEKILN_REPO, CODEKILN_HOME, CODEKILN_BIN, CODEKILN_CONFIG
set -euo pipefail

# The repository this installer belongs to.
DEFAULT_REPO="https://github.com/zonradkuse/codekiln.git"

say() { echo "codekiln: $*"; }
die() { echo "codekiln: $*" >&2; exit 1; }

# Everything runs from main(), called on the last line, so a download that is
# cut off midway cannot execute half of this script.
main() {
  local dest="${CODEKILN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/codekiln}"
  local bin_dir="${CODEKILN_BIN:-$HOME/.local/bin}"
  local config_dir="${CODEKILN_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/codekiln}"
  local modify_path=1 profile=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --no-modify-path) modify_path=0 ;;
      --profile) [[ $# -ge 2 ]] || die "--profile needs a name, e.g. --profile supervised-coding"; profile="$2"; shift ;;
      --profile=*) profile="${1#--profile=}" ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done

  command -v git >/dev/null || die "git is required"

  # Where to clone from: explicit override; else, when run from a checkout, that
  # checkout's origin; else the default above (the curl | bash case).
  local repo="${CODEKILN_REPO:-}" src_dir
  if [[ -z $repo && -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo="$(git -C "$src_dir" remote get-url origin 2>/dev/null || true)"
  fi
  repo="${repo:-$DEFAULT_REPO}"

  # --- program ----------------------------------------------------------------
  if [[ -d $dest/.git ]]; then
    say "updating $dest"
    git -C "$dest" pull --ff-only
  elif [[ -e $dest && -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    die "$dest exists and is not a codekiln checkout - move it away first"
  else
    say "cloning $repo into $dest"
    mkdir -p "$(dirname "$dest")"
    git clone "$repo" "$dest"
  fi

  # --- command ----------------------------------------------------------------
  mkdir -p "$bin_dir"
  chmod +x "$dest/bin/codekiln"
  ln -sfn "$dest/bin/codekiln" "$bin_dir/codekiln"
  say "linked $bin_dir/codekiln"

  # --- your own files -----------------------------------------------------------
  mkdir -p "$config_dir/skills" "$config_dir/layers" "$config_dir/network" "$config_dir/profiles"
  if [[ -n $profile ]]; then
    # Keeps an existing copy with your edits. An unknown name should not stop
    # the rest of an update.
    CODEKILN_CONFIG="$config_dir" "$dest/bin/codekiln" profile default "$profile" \
      || say "profile '$profile' not set - see the message above"
  fi

  # --- PATH ---------------------------------------------------------------------
  local on_path=0
  case ":$PATH:" in *":$bin_dir:"*) on_path=1 ;; esac

  if [[ $on_path -eq 0 ]]; then
    local path_expr="$bin_dir" rc line
    [[ $bin_dir == "$HOME/.local/bin" ]] && path_expr='$HOME/.local/bin'
    line="export PATH=\"$path_expr:\$PATH\"  # added by the codekiln installer"
    case "$(basename "${SHELL:-sh}")" in
      zsh)  rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
      bash) if [[ $(uname -s) == Darwin ]]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
      fish) rc="" ;;
      *)    rc="$HOME/.profile" ;;
    esac
    if [[ $modify_path -eq 0 ]]; then
      say "$bin_dir is not on your PATH - add it yourself"
    elif [[ -z $rc ]]; then
      say "$bin_dir is not on your PATH - run: fish_add_path $bin_dir"
    elif grep -qF "added by the codekiln installer" "$rc" 2>/dev/null; then
      say "PATH entry already in $rc - open a new terminal"
    else
      printf '\n%s\n' "$line" >>"$rc"
      say "added $bin_dir to PATH in $rc - open a new terminal or run: source $rc"
    fi
  fi

  command -v docker >/dev/null || say "note: docker was not found; codekiln needs it to build and run"

  cat <<MSG

Installed.
  program          $dest
  your layers      $config_dir/layers
  your skills      $config_dir/skills
  your allowlist   $config_dir/network/allowlist.txt
  your profiles    $config_dir/profiles

Next:
  codekiln build                 # base image; add layers, e.g. codekiln build cpp ts
  codekiln open <project>        # then "Reopen in Container" in VS Code
  codekiln allow <host>          # let containers reach another HTTPS host
  codekiln init <project> --profile supervised-coding  # opinionated coding guidelines
MSG
}

main "$@"
