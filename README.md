# PoolLint

PoolLint detects PostgreSQL and MySQL session state that leaks through
an Active Record connection pool.

A request can run `SET ROLE tenant_a`, acquire a session advisory lock, or
change a custom GUC. On MySQL it can change `time_zone` or retain a `GET_LOCK`.
If the request forgets to restore that state, Active Record returns the
connection to the pool and a later request silently inherits it.
PoolLint records suspicious SQL and verifies the connection at a pool
boundary before reporting the leak.

The gem observes and reports. It never resets application state automatically.

## Requirements

| Ruby | Rails / Active Record | PostgreSQL | MySQL |
| --- | --- | --- | --- |
| 3.2–3.4 | 7.1 | 16 (`pg`) | 8.4 (`mysql2`, `trilogy`) |
| 3.2–3.4 | 7.2 | 16 (`pg`) | 8.4 (`mysql2`, `trilogy`) |
| 3.2–3.4 | 8.0 | 16 (`pg`) | 8.4 (`mysql2`, `trilogy`) |

CI runs both databases and both MySQL adapters for every supported Ruby/Rails
combination. Rails main runs as an allowed-to-fail compatibility signal.
Unsupported adapters, including SQLite3, are left untouched.

## Installation

Add the gem to a Rails application:

```ruby
gem "poollint", "~> 0.1.0"
```

The Railtie installs the SQL subscriber and connection callbacks during boot.

## Configuration

```ruby
# config/initializers/poollint.rb
PoolLint.configure do |config|
  config.inspection_point = :checkout
  config.mode = :log
  config.inspection_timeout = 0.25
  config.check_probability = 1.0
  config.rebaseline_after_report = true

  config.watched_settings = PoolLint::DEFAULT_PG_SETTINGS
  config.mysql_watched_settings = PoolLint::DEFAULT_MYSQL_SETTINGS
  config.track_custom_gucs = true
  config.check_advisory_locks = true
  config.suspicion_log_size = 20

  # A hash allows selected values.
  config.allowed_settings = {
    "application_name" => /\Amy-app-/,
    "statement_timeout" => ->(value) { value.to_i <= 500 }
  }
  # Or use ["application_name"] to ignore every value for named settings.

  config.ignore_if = ->(report) { report.setting_changes.empty? }
end
```

Defaults have two axes:

| Environment | Inspection point | Report mode |
| --- | --- | --- |
| `test` | `:checkin` | `:raise` |
| all others | `:checkout` | `:log` |

`:raise` raises `PoolLint::LeakedSessionState`
(`PoolLint::LeakDetected` remains an alias). At `:checkin`, that mode
is intended for tests because callback exceptions can prevent a connection
from returning to the available queue.

`check_probability` samples dirty inspections only. Initial baseline capture is
never sampled. `inspection_timeout` is expressed in seconds. PostgreSQL applies
it with `SET LOCAL statement_timeout` in a short transaction; MySQL applies a
`MAX_EXECUTION_TIME` hint to inspector queries. The former millisecond accessor
remains available as `inspection_timeout_ms`.

### Inspection point trade-offs

| Point | Report timing | Pool mutex | Intended use |
| --- | --- | --- | --- |
| `:checkout` | next borrower | inspector runs outside it | production default |
| `:checkin` | leaking borrower | held for the full inspection | tests and controlled environments |

Checkout reporting is delayed until the connection is borrowed again. This is
the cost of avoiding database queries while Active Record holds the pool mutex.
Selecting `:checkin` outside test emits a startup warning. Runtime evidence for
Rails 7.1, 7.2, and 8.0 is recorded in
[`docs/pool_locking.md`](docs/pool_locking.md).

## Detection scope

| Database | Detected | Not detected |
| --- | --- | --- |
| PostgreSQL | session `SET` and `RESET` changes | `SET LOCAL` and `SET TRANSACTION` |
| PostgreSQL | `SET ROLE` and `SET SESSION AUTHORIZATION` | transaction-scoped advisory locks |
| PostgreSQL | custom GUCs such as `myapp.tenant_id` | temporary tables and `LISTEN` registrations |
| PostgreSQL | session advisory locks owned by the connection backend | prepared statements |
| MySQL | configured `@@SESSION` variables | unconfigured session variables |
| MySQL | `GET_LOCK` retained by the current connection | transaction metadata locks |

SQL classification accepts leading Query Logs or Marginalia comments, lowercase
keywords, and line breaks. Inspector SQL is guarded against re-entry. Suspicious
SQL is truncated to 200 characters and kept in a bounded per-connection ring.

`DEFAULT_PG_SETTINGS` contains `role`, `session_authorization`, `search_path`,
`statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, and
`default_transaction_read_only`. Set `track_custom_gucs = false` to stop adding
settings discovered from SQL to that list, or `check_advisory_locks = false` to
skip `pg_locks` inspection.

For a setting present in the initial baseline, the current value is compared
with that baseline. For a dynamically discovered setting absent from the
baseline, the current value is compared with PostgreSQL's `reset_val`. Custom
GUCs are not rows in `pg_settings`; their empty post-`RESET` value is treated as
the reset state. `role` and `session_authorization` are read with
`current_setting` because PostgreSQL 16 does not expose them in `pg_settings`.

Advisory lock inspection is restricted to `pid = pg_backend_pid()`. Locks owned
by another pooled connection cannot be attributed to the inspected connection
and are ignored.

`DEFAULT_MYSQL_SETTINGS` contains `sql_mode`, `time_zone`,
`transaction_isolation`, `transaction_read_only`, `lock_wait_timeout`, and
`max_execution_time`. Replace or extend `mysql_watched_settings` to inspect
other session variables. Variable names are validated before they are used in
inspector SQL.

MySQL user-level locks are confirmed through
`performance_schema.metadata_locks`, restricted to the thread whose
`PROCESSLIST_ID` is `CONNECTION_ID()`. Confirmed entries carry
`confidence: :confirmed`. If the metadata lock instrument is disabled or access
to Performance Schema is denied, PoolLint falls back to the observed
balance of `GET_LOCK`, `RELEASE_LOCK`, and `RELEASE_ALL_LOCKS`, and reports
`confidence: :inferred`. Inferred results can be conservative because SQL
observation cannot know whether `GET_LOCK` succeeded or resolve a dynamically
computed lock name.

## Suppression and notifications

Suppress reports emitted within a known-safe block:

```ruby
PoolLint.suppress do
  ActiveRecord::Base.connection_pool.with_connection do |connection|
    # A report emitted while borrowing or returning this connection is suppressed.
  end
end
```

Suppression does not disable dirty tracking. `ignore_if` receives the complete
report and can apply an application-specific policy.

Every non-ignored report emits `leaked_state.poollint` through
`ActiveSupport::Notifications`. Its payload contains `inspection_point`,
`setting_changes`, `advisory_locks`, `user_level_locks`, and `suspicions`.
Monitoring systems can subscribe without a hard dependency:

```ruby
ActiveSupport::Notifications.subscribe("leaked_state.poollint") do |event|
  SecurityEvents.publish("database_session_leak", event.payload)
end
```

When Kannuki is already loaded, PoolLint best-effort matches leaked
numeric advisory keys against `Kannuki::LockManager.current_locks` and adds the
human-readable lock name to the report. Kannuki is never required or loaded by
PoolLint.

## PgBouncer

Session state is meaningful only while a client is attached to the same
PostgreSQL backend. With PgBouncer session pooling, use the gem normally and
also configure PgBouncer's server reset behavior. Transaction or statement
pooling can switch backends between statements; application session settings
and session advisory locks are unsuitable in those modes, and reports may not
describe a single stable backend session.

## Failure safety

Unexpected timeout, disconnection, malformed response, logger, or policy
exceptions are converted to warnings so checkout/checkin can continue.
`PoolLint::LeakDetected` in explicit `:raise` mode is the sole intended
exception. Inspection stores a constant amount of state per connection: a
baseline, dirty keys, and a bounded suspicion ring.

## Performance

The non-dirty boundary path performs no SQL. From a source checkout, run the
local benchmark with:

```sh
bundle exec ruby benchmark/boundary_overhead.rb
```

On 2026-07-28, a local Apple Silicon / Ruby 4.0 run measured the non-dirty
boundary at **3.40 million iterations/second (293.8 ns/iteration)**. CI verifies
behavior rather than asserting a machine-specific timing threshold.

## Development

```sh
bundle install
docker compose up -d --wait postgres mysql
bundle exec rspec
bundle exec appraisal rails-7.1 rspec
bundle exec appraisal rails-7.2 rspec
bundle exec appraisal rails-8.0 rspec
bundle exec rubocop
bundle exec rake build
```

`DATABASE_URL` overrides the default local URL
`postgresql://postgres:postgres@127.0.0.1:55432/poollint_test`.
MySQL defaults to `root:mysql@127.0.0.1:33306/poollint_test`;
override it with `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`,
`MYSQL_USERNAME`, and `MYSQL_PASSWORD`.

## License

PoolLint is available under the MIT License.
