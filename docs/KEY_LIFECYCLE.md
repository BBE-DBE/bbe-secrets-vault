# KEY_LIFECYCLE — identity, recipients, rotation

## The two key files

| File | Type | Permissions | Purpose |
|---|---|---|---|
| `identity.txt` | private (X25519 secret key) | 0600 | Decrypts every `.age` file in the vault |
| `recipients.txt` | public (X25519 public key) | 0644 | Encryption target for `set` and `rotate` |

`recipients.txt` is derived from `identity.txt` on `init`. They are
**not independent** — losing `identity.txt` makes `recipients.txt`
useless because nothing can decrypt secrets that were encrypted to
the corresponding public key.

## Three levels of "rotation"

### A. Per-secret rotation (`rotate <name>`)

Re-encrypts ONE secret with a fresh ephemeral envelope. The vault
identity is unchanged. Useful when:

- A specific secret was last modified before a security event and
  you want a clean ciphertext on disk.
- You need to verify the secret can still be decrypted (rotate
  performs decrypt-then-encrypt as a side effect).

### B. Identity rotation (vault re-init)

Generates a new identity. Every existing `.age` file is now
unreadable until rewritten with the new identity. The workflow:

```bash
# 1. List what needs migrating.
secrets-vault.sh list >/tmp/secrets-to-migrate

# 2. Decrypt every secret to a temporary plaintext directory using
#    the OLD identity. Use a tmpfs mount if available.
mkdir -p /run/user/$UID/wtt-migrate && chmod 700 /run/user/$UID/wtt-migrate
while read -r name; do
  secrets-vault.sh get "$name" --quiet > "/run/user/$UID/wtt-migrate/$name"
done </tmp/secrets-to-migrate

# 3. Re-init the vault. The old identity backup lands at
#    identity.txt.backup.<timestamp> next to the new identity.txt.
secrets-vault.sh init --force

# 4. Re-encrypt each secret with the new identity.
while read -r name; do
  secrets-vault.sh set "$name" --stdin < "/run/user/$UID/wtt-migrate/$name"
done </tmp/secrets-to-migrate

# 5. Wipe the temporary plaintext directory.
shred -u /run/user/$UID/wtt-migrate/* 2>/dev/null || rm -f /run/user/$UID/wtt-migrate/*
rmdir /run/user/$UID/wtt-migrate
rm /tmp/secrets-to-migrate
```

A v0.2.0 `secrets-vault.sh rekey` subcommand will package this into
one atomic operation. v0.1.0 keeps the steps explicit so the
operator sees every plaintext-touching command.

### C. Recipient broadcast (multi-key encryption — v0.3.0)

The `recipients.txt` schema accepts ONE public key in v0.1.0. A
future v0.3.0 will accept multiple lines so the same `.age` file can
be decrypted by any of N identities (e.g. operator + recovery
escrow). The vault layout is forward-compatible — each line in
`recipients.txt` becomes a recipient passed to `age -e -R ...`.

## Loss / corruption recovery

| Scenario | Recovery |
|---|---|
| `identity.txt` deleted, no backup | Total loss. Re-init the vault, re-fetch every secret from its primary source. |
| `identity.txt` deleted, backup exists | `cp identity.txt.backup.<ts> identity.txt && chmod 0600 identity.txt`. Audit log gains an `identity_restored` event on next access. |
| One `.age` file corrupt | Re-fetch the secret from its source and `secrets-vault.sh set <name>` again. |
| `audit.jsonl` truncated | Recreate as empty; future events still append. Past events lost. The operator should treat this as a security event. |
| `recipients.txt` lost or wrong | Regenerate from the identity: `age-keygen -y identity.txt > recipients.txt && chmod 0644 recipients.txt`. |

## Backup recommendations

- **`identity.txt`** to a sealed envelope, hardware token, or
  password manager. NOT to the same machine.
- **`audit.jsonl`** to a write-once medium for forensic value.
  `rsync --append-only` against an immutable destination or daily
  copy to an off-machine location.
- **`secrets.d/*.age`** is encrypted; daily rsync to anywhere is
  safe.
- **`recipients.txt`** is public; safe to commit to a config repo
  alongside the operator's username for the pre-T-051 multi-recipient
  flow.

## Inventory

`secrets-vault.sh list --json` is the machine-readable inventory.
Pipe it to `jq` to derive size totals, oldest secret, etc.:

```bash
secrets-vault.sh list --json \
  | jq '[.[] | {name, age_days: ((now - (.mtime|fromdateiso8601))/86400|floor)}]
        | sort_by(-.age_days)
        | .[0:5]'
```
