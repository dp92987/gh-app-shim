[![hits](https://hits.deltapapa.io/github/dp92987/gh-app-shim.svg)](https://hits.deltapapa.io)

# gh-app-shim

A transparent drop-in replacement for the [`gh`](https://cli.github.com/) CLI
that authenticates as a **GitHub App** when (and only when) it runs inside a
Claude Code session.

## Why

When Claude Code creates pull requests, posts comments, or runs reviews, those
actions should appear as a bot — not as your personal account. This shim makes
that automatic without any special wrapper command or instructions in
`CLAUDE.md`: tools just call `gh` as usual.

## How it works

`~/.local/bin/gh` is a symlink to `bin/gh`, placed earlier on `PATH` than the
real `gh`. On every invocation it branches on the `CLAUDECODE` environment
variable, which Claude Code sets in its shell but a normal terminal does not:

| Caller                         | `CLAUDECODE` | Behavior                                   |
| ------------------------------ | ------------ | ------------------------------------------ |
| Claude Code (Bash tool)        | set          | mints a GitHub App installation token, runs the real `gh` as the bot |
| You, in a normal terminal      | unset        | passes straight through — your own `gh` auth, untouched |

The shim mints a short-lived GitHub App installation token from the App's
private key (a signed RS256 JWT exchanged for an installation token), caches it
~55 min in `$XDG_RUNTIME_DIR`/`/tmp`, and hands it to the real `gh` via
`GH_TOKEN`.

If it can't produce a valid installation token (an installation token always
starts with `ghs_`), it **refuses to run** rather than silently falling back to
your personal `gh` auth — so a Claude Code action can never accidentally be
attributed to your human account.

> Edge case: running `! gh ...` from inside a Claude Code session executes in
> Claude's environment (`CLAUDECODE=1`), so it acts as the bot. For your own
> actions, use a normal terminal.

## Install

```sh
git clone <this-repo> gh-app-shim
cd gh-app-shim
./install.sh
```

`install.sh` is idempotent and:

1. Finds a real `gh` on `PATH` (fails with install instructions if none — the
   GitHub CLI is a prerequisite, not something the shim installs).
2. Symlinks `bin/gh` → `~/.local/bin/gh`.
3. Seeds `~/.config/gh-app-shim/config.env` from `config.example.env` and pins
   `REAL_GH`.

Then finish setup:

1. Place the App private key at `KEY_PATH` (default
   `~/.config/gh-app-shim/app.pem`) and `chmod 600` it.
2. Check `APP_ID` / `INSTALLATION_ID` in `~/.config/gh-app-shim/config.env`.

## Verify

An App installation token is a *bot* credential with no associated human user,
so `gh api user` is **not** a valid bot check (that endpoint only works for a
human token). Probe an installation-only endpoint instead:

```sh
# as the bot — succeeds only with an installation token, lists the repos the
# App is installed on:
CLAUDECODE=1 gh api /installation/repositories --jq '.repositories[].full_name'

# as yourself — your own auth, untouched:
gh api user --jq .login                # -> your personal login
```

The bot can only act on repositories the GitHub App is installed on. Add or
remove repos from the App's installation in its GitHub settings.

### Troubleshooting

When `CLAUDECODE=1 gh api /installation/repositories` fails, the error tells you
which credential `gh` actually used:

| Error | Meaning | Fix |
| ----- | ------- | --- |
| `403 You must authenticate with an installation access token` | `gh` used your **personal** token, not the App's — the shim isn't on `PATH` first, or `CLAUDECODE` wasn't set | check `which gh` points at `~/.local/bin/gh`; the hardened shim now refuses this instead of impersonating you |
| `401 Bad credentials` | the installation token is **expired or invalid** | delete the cache (`rm "$XDG_RUNTIME_DIR"/gh-app-shim-token*`) so the shim re-mints; if it persists, re-check `APP_ID` / `INSTALLATION_ID` / `KEY_PATH` |
| `gh-app-shim: no valid installation token available` | the shim couldn't mint a token and stopped (by design) rather than acting as you | verify the `.pem` is readable and the config values are correct |

## Restore on a new machine

```sh
git clone <this-repo> && cd gh-app-shim && ./install.sh
# copy your app.pem to ~/.config/gh-app-shim/app.pem (chmod 600)
```

That's it — the shim, installer, and config template live in git; only the
`.pem` key and the filled-in `config.env` stay local (and are `.gitignore`d).

## Configuration

See [`config.example.env`](./config.example.env). The private key is the only
real secret; `APP_ID` and `INSTALLATION_ID` are identifiers, not credentials.

## Requirements

The [GitHub CLI (`gh`)](https://github.com/cli/cli#installation) must already be
installed — the shim wraps it, it doesn't install it. Plus `bash`, `curl`, and
`openssl` (for token minting).
