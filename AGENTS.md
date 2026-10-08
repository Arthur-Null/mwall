# Repository Operations

## Identify the machine before writing or publishing

Run `hostname` and `scutil --get LocalHostName` in the shell that will execute
repository commands. Both machines use `~/Code/mwall`, so the working directory
and username do not identify the machine. `SSH_CONNECTION` indicates an SSH
session but does not establish which machine is running it.

| Role | SSH destination | LocalHostName | Typical hostname |
| --- | --- | --- | --- |
| Primary development and publishing | `mba.sgponte` | `fangyuchendeMacBook-Air` | `fangyuchendeMacBook-Air.local` |
| Local debugging and pull synchronization | — | `MacBook-Pro-For-Work` | `MacBook-Pro-For-Work.local` |

`mba.sgponte` is an SSH destination alias; its system hostname is different.
Confirm the identity inside the remote session before modifying or publishing.
If the identity is unknown or these names have changed, verify the machine's
role before committing or pushing. Never infer publishing permission from the
repository path alone.

## Development and synchronization

- Prefer making code and documentation changes in `~/Code/mwall` on
  `mba.sgponte`, reached through SSH.
- Run validation, create commits, and push to the Git remote on that machine.
  Use Conventional Commits messages.
- On `MacBook-Pro-For-Work`, restrict local code changes to debugging. Use
  `git pull --ff-only` to synchronize repository history from the remote.
  Do not commit or run `git push` on this machine, including force pushes or
  pushes to another remote. Read-only Git inspection is allowed.
- Do not use `scp` for synchronization. Reproduce local debugging changes in
  the MBA repository through SSH edits or a reviewed patch applied by the
  remote `patch` command; do not use Git as a machine-to-machine transfer.

For local debugging changes that need to be kept:

1. Inspect both worktrees and preserve the local diff and any untracked files.
2. Update the MBA's branch from its Git remote, then apply the intended changes
   through SSH without overwriting unrelated work.
3. Validate, commit, and push on the MBA; verify the remote branch contains the
   resulting commit.
4. After confirming all local debugging changes are preserved in that commit,
   remove only the duplicated local edits and pull on the local machine.
5. Confirm both machines have the intended commit and report any remaining
   worktree changes. Preserve unrelated edits throughout the process.
