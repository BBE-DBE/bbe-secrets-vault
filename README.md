# bbe-secrets-vault

Tiny age-encrypted secret store for local agents. Replaces ad-hoc
`~/.bbe-coord-keys/`-style scattered keys with one append-only vault
per machine.

> **Status:** v0.1.0. License: MIT.
> **Crypto:** [age](https://age-encryption.org/) — system tool, not vendored.

## Why

Multi-agent setups accumulate keys: API tokens for Anthropic / OpenAI /
GitHub, symmetric keys for at-rest encryption (`bbe-coord` T-013),
service-account credentials. Storing them as plaintext under `~/`
loses three things:

- **Audit trail.** No record of which process read which secret when.
- **Rotation.** Editing a key in five places is brittle.
- **Inventory.** Operator can't list "what does this machine know?"
  without grepping multiple directories.

`bbe-secrets-vault` is a 600-line bash + age wrapper that puts every
secret behind one identity, every read into one append-only audit log,
and every rotation into one explicit subcommand.

## Install

```bash
git clone https://github.com/BBE-DBE/bbe-secrets-vault.git ~/.bbe-secrets-vault
cd /any/working/dir
~/.bbe-secrets-vault/install.sh
```

`install.sh` checks for `age` and prints the install hint for your
package manager if it's missing (`brew install age` /
`apt install age` / `dnf install age`). Then it points you at
`secrets-vault.sh init` to create the vault.

## Daily use

```bash
secrets-vault.sh init                    # creates ~/.bbe-vault/
secrets-vault.sh set api-anthropic       # interactive (terminal hidden)
secrets-vault.sh get api-anthropic       # to stdout
secrets-vault.sh list                    # secret NAMES, never values
secrets-vault.sh rotate api-anthropic    # re-encrypts with current identity
secrets-vault.sh audit --since 2026-05-01
```

Set the secret value via stdin pipe to keep it out of shell history:

```bash
op item get "Anthropic API" --field credential | secrets-vault.sh set api-anthropic --stdin
```

## Layout (`~/.bbe-vault/`)

```
~/.bbe-vault/
├── identity.txt            # PRIVATE age key (mode 0600). Never commit.
├── recipients.txt          # PUBLIC age key(s) — encryption targets.
├── secrets.d/
│   ├── api-anthropic.age   # age -e -R recipients.txt
│   ├── api-openai.age
│   └── inbox-bbe-coord-v1.age
└── audit.jsonl             # append-only, one JSON event per line
```

`BBE_VAULT_HOME` overrides the default `~/.bbe-vault/` location —
useful for sandboxed tests and per-tenant vaults.

## Audit log

Every `set` / `get` / `rotate` appends one JSON line to
`audit.jsonl` with timestamp (ISO-8601 UTC `Z`), action, secret
name (NOT value), and operator-set caller name (`$BBE_VAULT_ACTOR`,
defaults to `$USER`). See [`docs/AUDIT_LOG_FORMAT.md`](docs/AUDIT_LOG_FORMAT.md).

## Security model

- **age is system-installed**, not bundled. The toolkit refuses to
  run if `age` is absent and tells you how to install it.
- **`identity.txt` is the only secret-bearing file.** Permissions
  set to `0600` on init. Lose it = lose every secret. Back up
  separately to a sealed envelope, hardware token, or password
  manager.
- **`recipients.txt` is public.** It's the X25519 public key
  derived from the identity. Sharing it does not weaken the vault.
- **Audit log is append-only by convention.** Filesystem-level
  enforcement (`chattr +a`) requires root and is not toolkit
  responsibility. Every code path uses `>>` redirects only.
- **Secret values never hit `set -x` traces.** `set` reads via
  `read -rs` (terminal disabled) or stdin pipe; `get` writes
  directly to stdout, never to a logged variable.

## Backwards compatibility — `~/.bbe-coord-keys/` (T-013)

`bbe-coord` T-013 stores at-rest encryption keys as raw bytes at
`~/.bbe-coord-keys/<repo>-v<N>.bin`. The vault reads these via the
optional `secrets-vault.sh migrate-from-bbe-coord-keys --dry-run`
subcommand, which encrypts each `.bin` file as a vault secret named
`<basename-without-extension>`. After migration, T-013 callers can
fetch the bytes back via `secrets-vault.sh get <name>` (binary-safe
stdout pipe).

## Files this toolkit ships

| Path | Purpose |
|---|---|
| `install.sh` | dependency check + first-time hint |
| `secrets-vault.sh` | top-level CLI dispatcher |
| `vault-lib/init.sh` | `init` subcommand |
| `vault-lib/set.sh` | `set` subcommand |
| `vault-lib/get.sh` | `get` subcommand |
| `vault-lib/list.sh` | `list` subcommand |
| `vault-lib/rotate.sh` | `rotate` subcommand |
| `vault-lib/audit.sh` | `audit` subcommand |
| `docs/QUICKSTART.md` | five-minute walkthrough |
| `docs/KEY_LIFECYCLE.md` | identity / rotation guide |
| `docs/AUDIT_LOG_FORMAT.md` | event shape |
| `tests/run-all.sh` | runs every test |

## Constraints

- Bash 4+, GNU coreutils. Tested on Linux.
- `age` ≥ 1.0 required at runtime; tests **SKIP** lifecycle checks
  cleanly when `age` is absent so the suite still passes on
  age-less CI.
- `jq` required for the audit log; `command -v` checked at startup.

## License

MIT — see [`LICENSE`](LICENSE).
