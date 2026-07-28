# Active Record pool callback spike

This document records the behavior that determines PoolLint's default
inspection point. The results were measured against PostgreSQL 16 on 2026-07-28
with `scripts/spikes/pool_locking.rb`.

## Results

| Active Record | `_run_checkout_callbacks` owns pool mutex | `_run_checkin_callbacks` owns pool mutex | checkout callback exception | checkin callback exception |
| --- | --- | --- | --- | --- |
| 7.1.6 | no | yes | connection removed; next checkout succeeds | connection stranded; next checkout times out |
| 7.2.3 | no | yes | connection removed; next checkout succeeds | connection stranded; next checkout times out |
| 8.0.2 | no | yes | connection removed; next checkout succeeds | connection stranded; next checkout times out |

Run an individual measurement with:

```sh
AR_VERSION=7.2.3 ruby scripts/spikes/pool_locking.rb
```

The source layout agrees with the runtime probe. In all three versions,
`ConnectionPool#checkin` enters the pool's `synchronize` block before invoking
`_run_checkin_callbacks`. `checkout_and_verify` invokes
`_run_checkout_callbacks` after `acquire_connection` has left that critical
section.

## Decision

The default inspection point is `:checkout`.

- Inspector queries at checkout do not hold the pool mutex.
- A slow inspection delays only the borrower receiving that connection.
- A leak is reported on the next borrow instead of at the end of the leaking
  borrow.

`:checkin` remains available for tests and tightly controlled environments. It
runs under the pool mutex, so inspector latency blocks pool operations. All
unexpected inspector errors must be converted to warnings at either inspection
point. Raising from a checkin callback can strand the connection before it is
returned to the available queue.

## PostgreSQL setting spike

PostgreSQL 16 does not expose `role` or `session_authorization` as rows in
`pg_settings`. Both are readable with `current_setting`:

```sql
SELECT current_setting('role'),
       current_setting('session_authorization');
```

The inspector therefore reads requested settings through `current_setting` and
left joins `pg_settings` for `reset_val`. This keeps ordinary GUCs in one batch
while supporting the two special settings and custom GUCs.

For an ordinary GUC, `reset_val` remains the session default across
`SET`/`RESET`. A custom GUC is absent from `pg_settings`; after `RESET`,
`current_setting(name, true)` returns an empty string. The inspector treats an
empty custom value as its reset state.
