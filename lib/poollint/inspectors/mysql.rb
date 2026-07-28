# frozen_string_literal: true

module PoolLint
  module Inspectors
    class MySQL
      Snapshot = Struct.new(:settings, :user_level_locks, keyword_init: true)
      class PerformanceSchemaUnavailable < StandardError; end

      SETTING_NAME = /\A[a-z_][a-z0-9_]*\z/

      INSTRUMENT_SQL = <<~SQL
        SELECT /*+ MAX_EXECUTION_TIME(%<timeout_ms>d) */ COUNT(*)
          FROM performance_schema.setup_instruments
         WHERE NAME = 'wait/lock/metadata/sql/mdl'
           AND ENABLED = 'YES'
      SQL

      USER_LOCKS_SQL = <<~SQL
        SELECT /*+ MAX_EXECUTION_TIME(%<timeout_ms>d) */
               ml.OBJECT_NAME AS name,
               ml.LOCK_TYPE AS mode,
               ml.LOCK_STATUS AS status
          FROM performance_schema.metadata_locks ml
          JOIN performance_schema.threads t
            ON t.THREAD_ID = ml.OWNER_THREAD_ID
         WHERE ml.OBJECT_TYPE = 'USER LEVEL LOCK'
           AND ml.LOCK_STATUS = 'GRANTED'
           AND t.PROCESSLIST_ID = CONNECTION_ID()
         ORDER BY ml.OBJECT_NAME
      SQL

      def initialize(configuration)
        @configuration = configuration
        @allowed_settings = AllowedSettings.new(configuration.allowed_settings)
      end

      def establish_baseline(connection, state)
        snapshot = capture_snapshot(connection, state)
        state.capture_baseline(snapshot)
        ConnectionState.attach(connection, state)
        snapshot
      end

      def inspect(connection, state, inspection_point:)
        baseline = state.baseline
        return establish_baseline(connection, state) unless baseline
        return unless state.dirty?

        snapshot = capture_snapshot(connection, state)
        unless state_attached?(connection, state)
          return reattach_after_reconnect(connection, state, snapshot)
        end

        report = build_report(baseline, snapshot, state, inspection_point)
        state.finish_inspection(
          snapshot: snapshot,
          rebaseline: report.leak? && @configuration.rebaseline_after_report
        )
        report if report.leak?
      end

      private

      def build_report(baseline, snapshot, state, inspection_point)
        Report.new(
          inspection_point: inspection_point,
          setting_changes: setting_changes(baseline, snapshot),
          advisory_locks: [],
          user_level_locks: user_lock_changes(baseline, snapshot),
          suspicions: state.suspicions
        )
      end

      def capture_confirmed_user_locks(connection)
        sql = format(INSTRUMENT_SQL, timeout_ms: inspection_timeout_ms)
        enabled = connection.select_value(sql, "PoolLint")
        if enabled.to_i.zero?
          raise PerformanceSchemaUnavailable, "metadata lock instrument is disabled"
        end

        locks_sql = format(USER_LOCKS_SQL, timeout_ms: inspection_timeout_ms)
        connection.select_all(locks_sql, "PoolLint").map do |row|
          UserLevelLock.new(
            name: row.fetch("name"),
            mode: row["mode"],
            status: row["status"],
            confidence: :confirmed
          )
        end
      end

      def capture_settings(connection)
        names = @configuration.mysql_watched_settings
        validate_setting_names!(names)
        selections = names.map do |name|
          "@@SESSION.#{name} AS #{connection.quote_column_name(name)}"
        end
        sql = "SELECT /*+ MAX_EXECUTION_TIME(#{inspection_timeout_ms}) */ #{selections.join(', ')}"
        connection.select_one(sql, "PoolLint").to_h do |name, value|
          [name, value.to_s]
        end
      end

      def capture_snapshot(connection, state)
        ExecutionState.while_inspecting do
          Snapshot.new(
            settings: capture_settings(connection),
            user_level_locks: capture_user_locks(connection, state)
          )
        end
      end

      def capture_user_locks(connection, state)
        capture_confirmed_user_locks(connection)
      rescue StandardError => e
        PoolLint.log_warning(
          "MySQL user-level lock inspection is inferred after #{e.class}: #{e.message}"
        )
        inferred_user_locks(state)
      end

      def inferred_user_locks(state)
        state.inferred_user_locks.map do |name, count|
          UserLevelLock.new(name: name, acquisition_count: count, confidence: :inferred)
        end
      end

      def inspection_timeout_ms
        (@configuration.inspection_timeout * 1000).ceil
      end

      def reattach_after_reconnect(connection, state, snapshot)
        state.capture_baseline(snapshot)
        ConnectionState.attach(connection, state)
        nil
      end

      def setting_changes(baseline, snapshot)
        names = baseline.settings.keys | snapshot.settings.keys
        names.filter_map do |name|
          expected = baseline.settings[name]
          current = snapshot.settings[name]
          next if expected == current
          next if @allowed_settings.allow?(name, current)

          SettingChange.new(
            name: name,
            baseline: expected,
            current: current,
            comparison: :baseline
          )
        end
      end

      def state_attached?(connection, state)
        ConnectionState.attached?(connection, state)
      end

      def user_lock_changes(baseline, snapshot)
        baseline_fingerprints = baseline.user_level_locks.map(&:fingerprint)
        snapshot.user_level_locks.reject do |lock|
          baseline_fingerprints.include?(lock.fingerprint)
        end
      end

      def validate_setting_names!(names)
        invalid = names.grep_v(SETTING_NAME)
        return if invalid.empty?

        raise ArgumentError, "invalid MySQL session variables: #{invalid.join(', ')}"
      end
    end
  end
end
