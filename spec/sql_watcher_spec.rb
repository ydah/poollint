# frozen_string_literal: true

RSpec.describe PoolLint::SqlWatcher do
  describe ".detect" do
    {
      "SET search_path TO tenant_1" => [:set, "search_path"],
      "set statement_timeout = 250" => [:set, "statement_timeout"],
      "/*application:shop*/ SET ROLE tenant" => [:set, "role"],
      "-- query log\nSET SESSION AUTHORIZATION tenant" => [:set, "session_authorization"],
      "SET\nTIME ZONE 'UTC'" => [:set, "timezone"],
      "SET SESSION application_name = 'worker'" => [:set, "application_name"],
      "SET NAMES 'UTF8'" => [:set, "client_encoding"],
      "SET SCHEMA tenant_1" => [:set, "search_path"],
      "RESET search_path" => [:reset, "search_path"],
      "reset all;" => [:reset, nil]
    }.each do |sql, expected|
      it "classifies #{sql.inspect}" do
        detection = described_class.detect(sql)

        expect([detection.kind, detection.setting]).to eq(expected)
      end
    end

    [
      "SET LOCAL search_path = tenant_1",
      "set transaction isolation level serializable",
      "SET CONSTRAINTS ALL DEFERRED",
      "SELECT 1"
    ].each do |sql|
      it "ignores #{sql.inspect}" do
        expect(described_class.detect(sql)).to be_nil
      end
    end

    [
      "SELECT pg_advisory_lock(42)",
      "select pg_try_advisory_lock(42)",
      "SELECT pg_advisory_lock_shared(42)",
      "SELECT pg_try_advisory_lock_shared(42)",
      "SELECT pg_advisory_unlock(42)",
      "SELECT pg_advisory_unlock_shared(42)",
      "SELECT pg_advisory_unlock_all()",
      "/* marginalia */ SELECT pg_advisory_lock(1, 2)",
      "-- query\nSELECT\npg_advisory_lock(42)",
      "SELECT CASE WHEN true THEN pg_advisory_lock(42) END"
    ].each do |sql|
      it "tracks session advisory call #{sql.inspect}" do
        expect(described_class.detect(sql)&.kind).to eq(:advisory_lock)
      end
    end

    it "ignores transaction advisory locks" do
      expect(described_class.detect("SELECT pg_advisory_xact_lock(42)")).to be_nil
    end
  end

  describe ".process" do
    it "marks the payload connection dirty" do
      connection = Object.new

      described_class.process(
        connection: connection,
        name: "SQL",
        sql: "SET myapp.tenant_id = '42'"
      )

      state = PoolLint.connection_state(connection)
      expect(state).to be_dirty
      expect(state.monitored_settings).to eq(["myapp.tenant_id"])
    end

    it "does not observe inspector SQL" do
      connection = Object.new

      PoolLint::ExecutionState.while_inspecting do
        described_class.process(
          connection: connection,
          name: "SQL",
          sql: "SET statement_timeout = 250"
        )
      end

      expect(PoolLint.connection_state(connection)).not_to be_dirty
    end

    it "does not dynamically monitor custom GUCs when tracking is disabled" do
      connection = Object.new
      PoolLint.configuration.track_custom_gucs = false

      described_class.process(
        connection: connection,
        name: "SQL",
        sql: "SET myapp.tenant_id = '42'"
      )

      state = PoolLint.connection_state(connection)
      expect(state).to be_dirty
      expect(state.monitored_settings).to be_empty
    ensure
      PoolLint.configuration.track_custom_gucs = true
    end
  end
end
