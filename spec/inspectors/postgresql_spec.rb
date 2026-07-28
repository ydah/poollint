# frozen_string_literal: true

RSpec.describe PoolLint::Inspectors::PostgreSQL, :postgresql do
  def mark_dirty(state, setting: nil, kind: :set)
    state.mark_dirty(
      kind: kind,
      setting: setting,
      sql: setting ? "SET #{setting} = 'leaked'" : "SELECT pg_advisory_lock(42)",
      call_site: "postgresql_spec.rb:1"
    )
  end

  around do |example|
    PoolLint.reset_configuration!(environment: "production")
    with_postgresql_connection do |connection|
      @connection = connection
      @state = PoolLint.connection_state(connection)
      @inspector = described_class.new(PoolLint.configuration)
      @inspector.establish_baseline(connection, @state)
      example.run
    end
  end

  it "reports an ordinary GUC against reset_val when it was absent from the baseline" do
    @connection.execute("SET application_name = 'leaked-worker'")
    mark_dirty(@state, setting: "application_name")

    report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(report.setting_changes.first.to_h).to include(
      name: "application_name",
      current: "leaked-worker",
      comparison: :reset_value
    )
  end

  it "detects a leaked statement_timeout without observing the inspector timeout" do
    @connection.execute("SET statement_timeout = '2s'")
    mark_dirty(@state, setting: "statement_timeout")

    report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(report.setting_changes.first.to_h).to include(
      name: "statement_timeout",
      baseline: "0",
      current: "2s"
    )
  end

  it "does not report a GUC that was reset" do
    @connection.execute("SET application_name = 'temporary'")
    @connection.execute("RESET application_name")
    mark_dirty(@state, setting: "application_name")

    expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
  end

  it "reports a custom GUC and treats its empty value as reset" do
    @connection.execute("SET myapp.tenant_id = '42'")
    @connection.execute("RESET myapp.tenant_id")
    mark_dirty(@state, setting: "myapp.tenant_id", kind: :reset)
    expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil

    @connection.execute("SET myapp.tenant_id = '42'")
    mark_dirty(@state, setting: "myapp.tenant_id")
    report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(report.setting_changes.first.current).to eq("42")
  end

  it "reads role even though it is absent from pg_settings" do
    @connection.execute("SET ROLE postgres")
    mark_dirty(@state, setting: "role")

    report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(report.setting_changes.first.to_h).to include(
      name: "role",
      baseline: "none",
      current: "postgres",
      comparison: :baseline
    )
  end

  it "reports only advisory locks owned by the inspected backend" do
    @connection.execute("SELECT pg_advisory_lock(42)")
    mark_dirty(@state, kind: :advisory_lock)

    report = @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(report.advisory_locks.map(&:object_key)).to include("42")
  end

  it "skips advisory lock queries when lock inspection is disabled" do
    PoolLint.configuration.check_advisory_locks = false
    inspector = described_class.new(PoolLint.configuration)
    inspector.establish_baseline(@connection, @state)
    @connection.execute("SELECT pg_advisory_lock(43)")
    mark_dirty(@state, kind: :advisory_lock)

    expect(inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
  ensure
    @connection.execute("SELECT pg_advisory_unlock_all()")
  end

  it "does not report an advisory lock owned by another backend" do
    pool = PoolLintPostgreSQLRecord.connection_pool
    other_connection = pool.checkout
    reset_postgresql_session(other_connection)
    other_connection.execute("SELECT pg_advisory_lock(99)")
    mark_dirty(@state, kind: :advisory_lock)

    expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
  ensure
    if other_connection
      reset_postgresql_session(other_connection)
      pool.checkin(other_connection)
    end
  end

  it "raises a specific error when an inspector query exceeds the timeout" do
    PoolLint.configuration.inspection_timeout = 0.001
    slow_inspector_class = Class.new(described_class) do
      private

      def capture_snapshot(connection, _names)
        connection.execute("SELECT pg_sleep(0.05)")
      end
    end
    slow_inspector = slow_inspector_class.new(PoolLint.configuration)
    mark_dirty(@state, setting: "application_name")

    expect { slow_inspector.inspect(@connection, @state, inspection_point: :checkout) }
      .to raise_error(PoolLint::InspectionTimeout)
  end

  it "restores the caller's statement_timeout after inspection" do
    original = @connection.select_value("SHOW statement_timeout")
    @connection.execute("SET application_name = 'temporary'")
    @connection.execute("RESET application_name")
    mark_dirty(@state, setting: "application_name")

    @inspector.inspect(@connection, @state, inspection_point: :checkout)

    expect(@connection.select_value("SHOW statement_timeout")).to eq(original)
  end

  it "rebaselines after a report so the same leak is not reported twice" do
    @connection.execute("SET application_name = 'leaked-worker'")
    mark_dirty(@state, setting: "application_name")
    @inspector.inspect(@connection, @state, inspection_point: :checkout)
    mark_dirty(@state, setting: "application_name")

    expect(@inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
  end

  it "applies allowed_settings to the current value" do
    PoolLint.configuration.allowed_settings = {
      "application_name" => "allowed-worker"
    }
    inspector = described_class.new(PoolLint.configuration)
    @connection.execute("SET application_name = 'allowed-worker'")
    mark_dirty(@state, setting: "application_name")

    expect(inspector.inspect(@connection, @state, inspection_point: :checkout)).to be_nil
  end
end
