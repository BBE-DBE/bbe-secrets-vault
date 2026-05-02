# AUDIT_LOG_FORMAT

`audit.jsonl` is one JSON object per line. Append-only by
convention; every code path uses `>>` redirects, never `>`.
File permissions tighten to `0600` on every write.

## Required fields

| Field | Type | Notes |
|---|---|---|
| `timestamp` | string | ISO-8601 UTC with literal `Z` (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`). |
| `action` | string | One of: `init`, `init_noop`, `set`, `get`, `list`, `rotate`. New actions in future versions are additive; consumers should ignore unknown actions. |
| `secret_name` | string \| null | The named secret. `null` for actions that don't operate on a single secret (`list`, `init`). MUST match the validation regex `^[a-z0-9][a-z0-9._-]{0,63}$`. |
| `actor` | string | The caller's identity. Comes from `BBE_VAULT_ACTOR` env var, falls back to `$USER`, falls back to `unknown`. |
| `pid` | integer | Process id of the invoking shell. Useful for cross-referencing with system audit logs. |

## Action-specific extras

Every event is the union of the required fields plus an
action-specific `extra` JSON object inlined into the same record.

### `init` / `init_noop`

```json
{"timestamp":"2026-05-03T07:55:01Z","action":"init","secret_name":null,"actor":"dev","pid":1234,"public_key":"age1abc...","force":false}
```

`init_noop` records a re-run on an already-initialised vault.
`init --force` writes one event with `force: true` AND backs up the
old identity to `identity.txt.backup.<timestamp>`.

### `set`

```json
{"timestamp":"...","action":"set","secret_name":"api-anthropic","actor":"dev","pid":1234,"ciphertext_path_only":true}
```

`set` does NOT log the value or the size of the plaintext — the
ciphertext-only flag exists to make the limit explicit to log
analysers.

### `get`

```json
{"timestamp":"...","action":"get","secret_name":"api-anthropic","actor":"dev","pid":1234,"exit_code":0,"stdout_was_tty":false}
```

`stdout_was_tty: true` indicates the secret was printed to a
terminal. Aggregating these tells the operator how often secrets
leak to screens vs flow into pipes.

### `list`

```json
{"timestamp":"...","action":"list","secret_name":null,"actor":"dev","pid":1234,"count":3}
```

`count` is the number of secrets the caller saw at that moment.

### `rotate`

```json
{"timestamp":"...","action":"rotate","secret_name":"api-anthropic","actor":"dev","pid":1234,"old_ciphertext_bytes":252,"new_ciphertext_bytes":252}
```

Ciphertext sizes typically match because age's overhead is
deterministic for a given plaintext length; differences flag a
plaintext-size change between rotations (operator should investigate).

## Querying

```bash
# Last 20 events, pretty:
secrets-vault.sh audit --tail 20

# Everything since 2026-05-01, JSON-only:
secrets-vault.sh audit --since 2026-05-01 --json

# Just the get operations on api-anthropic, this week:
secrets-vault.sh audit --since 2026-04-26 --action get --json \
  | jq 'select(.secret_name == "api-anthropic")'
```

## What is NOT in the log

- **Secret values.** Never. `get` records the access; the value
  flows directly to stdout.
- **Plaintext sizes.** Knowing a secret is "32 bytes" leaks the
  format (likely an OpenAI key); the log records ciphertext size
  only, which has a fixed overhead.
- **Stack traces.** A failure inside `set` or `get` exits with a
  status code; the audit log records the action, not the error
  message.
- **Caller's working directory.** Out of scope for v0.1.0; the
  `pid` is sufficient for tracing back if you correlate with
  shell-history or process-accounting tools.

## Schema versioning

v0.1.0 events do not carry a `schema_version` field. v0.2.0 will
introduce one as required; v0.1.0 events without the field default
to schema_version=1 by consumer convention.
