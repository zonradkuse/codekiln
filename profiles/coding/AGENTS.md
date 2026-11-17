<!--
  codekiln coding guidelines (starter).

  codekiln copied this file to ~/.config/codekiln/profiles/coding/AGENTS.md.
  That copy is yours: edit it freely; `codekiln update` never overwrites it.
  It is mounted read-only into the containers of projects that use this
  profile (`codekiln init <project> --profile coding`), and loaded by any
  harness that is wired to it.
-->

# Coding guidelines

These apply unless the project's own instructions
(AGENTS.md, CLAUDE.md, CONTRIBUTING, etc.) say otherwise. Project
instructions win over these; the sandbox rules win over both.

## Before changing code
- Read the relevant code first and find out how the project already solves
  similar problems. Reuse existing helpers, patterns and libraries.
- If the request is ambiguous in a way that changes the result, ask one
  focused question. Otherwise pick the conventional option and say which.
- For anything larger than a small fix, state the plan in a few lines before
  editing.

## Making changes
- Keep the diff as small as the task allows. No drive-by refactors, renames,
  reformatting or dependency bumps; mention them as suggestions instead.
- Match the surrounding style: naming, structure, error handling, comment
  density. Run the project's formatter and linter if it has them.
- Prefer clear, boring code over clever code. Small functions, explicit names,
  no dead code, no commented-out code.
- Handle errors where they can be handled; otherwise let them surface with
  context. Never swallow an error silently.
- Do not add a dependency without saying why and asking first. Prefer the
  standard library and what the project already uses.
- Comments explain why, not what. Update comments and docs that your change
  makes wrong.
- Never put secrets, tokens or personal data in code, tests, logs or commits.

## Tests and verification
- Run the existing tests that cover the change. Add or update tests for new
  behaviour and for every bug fix (a test that fails without the fix).
- Before saying something works, run it. If you could not run or test it, say
  so explicitly and explain what remains unverified.
- Report failures as they are, with the relevant output. Do not weaken,
  skip or delete a test to make it pass.

## Git
- Work on a branch, not on the default branch, unless told otherwise.
- Commit only when asked. One logical change per commit, with a message that
  says what changed and why.
- Never rewrite published history, and never push (see the sandbox rules).

## Communication
- Be brief. Lead with the result, then what you changed, then anything the
  user has to decide or do.
- Reference code as `path:line`.
