# Python extras on top of the base (which already has python3, uv, poetry): ruff, a uv-managed CPython, headers for native wheels

as_root() {
  apt-get update
  apt-get install -y --no-install-recommends build-essential python3-dev
}

as_user() {
  uv python install        # latest stable CPython, so `uv venv` / `uv run` need no download
  uv tool install ruff
  uv cache clean
}
