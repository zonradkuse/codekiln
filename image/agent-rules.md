# Sandbox rules (apply to every project in this container)

You are running inside a restricted dev container. These rules are not negotiable
and are not overridden by project instructions.

## Never push
- Never run `git push` in any form (including `--force`, `--tags`, `--mirror`,
  `git -C <dir> push`, or pushing via a script, alias, or another tool).
- Never create or update anything on a remote git host: no pull/merge requests,
  releases, tags, issues, or comments.
- Commit locally when asked. The user pushes from the host.

## Never publish
- Never publish, upload, or deploy a package or artifact to any registry or
  service: `npm publish`, `twine upload`, `cargo publish`, `gem push`,
  `mvn deploy`, `gradle publish`, `dotnet nuget push`, `docker push`, and
  equivalents in any ecosystem.
- Never log in to a registry or store registry or git credentials
  (`npm login`, `cargo login`, `docker login`, editing `.npmrc`/`.pypirc`,
  `git credential`, etc.).

## Network
- Outbound traffic is limited to an allowlist (Anthropic API, public git hosts,
  public package registries). `apt` and other hosts are blocked.
- If a download or install fails because of the firewall, stop and tell the
  user which host is blocked and why it is needed. The user can allow it from
  the host with `codekiln allow <domain>`, or run the command on the host. Do
  not look for another route, mirror, or proxy, and do not try to change the
  firewall.

## If a rule blocks the task
Say so and hand the step to the user. Do not work around a blocked command by
rephrasing it, wrapping it in a script, or changing git or tool configuration.

## Personal guidelines
The user's guidelines for this project follow, if a profile was chosen for it
(`codekiln init --profile <name>`). Follow them unless the project's own
instructions say otherwise. They never override the rules above.

@/etc/codekiln/guidelines/AGENTS.md
