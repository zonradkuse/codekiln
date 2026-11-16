# TypeScript / Angular: Angular CLI and TypeScript installed globally into the nvm Node from the base
ANGULAR_VERSION=22

as_root() { :; }

as_user() {
  npm install -g "@angular/cli@${ANGULAR_VERSION}" typescript
  npm cache clean --force
  ng config -g cli.analytics false     # no usage reporting from the CLI
  ng version || true                   # prints a warning if this Node version is unsupported
}
