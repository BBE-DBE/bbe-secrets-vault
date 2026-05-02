# QUICKSTART — bbe-secrets-vault in 5 minutes

## Prerequisites

- bash ≥ 4
- [age](https://age-encryption.org/) (`brew install age` /
  `apt install age` / `dnf install age`)
- jq

`install.sh` checks all three and prints the install hint for your
package manager when one is missing.

## 1. Clone and check

```bash
git clone https://github.com/BBE-DBE/bbe-secrets-vault.git ~/.bbe-secrets-vault
~/.bbe-secrets-vault/install.sh
```

Output should end with `OK — bbe-secrets-vault 0.1.0 prerequisites
satisfied`.

## 2. Initialise the vault

```bash
~/.bbe-secrets-vault/secrets-vault.sh init
```

Creates:
- `~/.bbe-vault/identity.txt` (private age key, mode 0600)
- `~/.bbe-vault/recipients.txt` (public X25519 key)
- `~/.bbe-vault/secrets.d/` (empty, mode 0700)
- `~/.bbe-vault/audit.jsonl` (one `init` event written immediately)

**Back up `identity.txt` somewhere safe.** Losing it loses every
secret in the vault.

## 3. Store a secret

Interactive (terminal echo disabled):

```bash
~/.bbe-secrets-vault/secrets-vault.sh set api-anthropic
# Secret value for api-anthropic (input hidden):
# Confirm:
# secrets-vault: stored api-anthropic
```

From a pipe (keeps the value out of shell history):

```bash
op item get "Anthropic API" --field credential \
  | ~/.bbe-secrets-vault/secrets-vault.sh set api-anthropic --stdin
```

## 4. Read it back

```bash
~/.bbe-secrets-vault/secrets-vault.sh get api-anthropic
# (prints the plaintext to stdout)
```

When the destination is a terminal, a one-line warning goes to
stderr: `(printing secret api-anthropic to terminal — pipe to
consume safely)`. Pipes don't trigger the warning.

```bash
ANTHROPIC_API_KEY=$(secrets-vault.sh get api-anthropic --quiet) my-agent
```

## 5. Inventory

```bash
~/.bbe-secrets-vault/secrets-vault.sh list
# api-anthropic
# api-openai
```

`list` never prints values. `--json` adds `size_bytes` and `mtime`
metadata for tooling.

## 6. Rotate

```bash
~/.bbe-secrets-vault/secrets-vault.sh rotate api-anthropic
# secrets-vault: rotated api-anthropic (ciphertext 252 -> 252 bytes)
```

`rotate` re-encrypts the secret in place: the value stays the same,
the ciphertext changes. See [`KEY_LIFECYCLE.md`](KEY_LIFECYCLE.md)
for the full identity-rotation workflow.

## 7. Audit

```bash
~/.bbe-secrets-vault/secrets-vault.sh audit --tail 5
# TIMESTAMP             ACTION      SECRET_NAME    ACTOR
# 2026-05-02T22:15:01Z  set         api-anthropic  dev
# 2026-05-02T22:15:08Z  get         api-anthropic  dev
# ...
```

`audit.jsonl` is the source of truth; the pretty view never prints
secret values. See [`AUDIT_LOG_FORMAT.md`](AUDIT_LOG_FORMAT.md) for
the schema.

## Per-tenant vaults

Set `BBE_VAULT_HOME` to point at a non-default location:

```bash
export BBE_VAULT_HOME=~/customer-acme/.bbe-vault
secrets-vault.sh init
secrets-vault.sh set api-stripe
```

Each `BBE_VAULT_HOME` is independent — separate identity, separate
audit log. This is the building block for the future fork-machine
multi-tenant API-key separation.
