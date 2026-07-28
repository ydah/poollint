# frozen_string_literal: true

module PoolLint
  module Inspectors
    class PostgreSQL
      SPECIAL_SETTINGS = %w[role session_authorization].freeze
      Snapshot = Struct.new(:settings, :advisory_locks, keyword_init: true)
      SettingValue = Struct.new(:setting, :reset_value, keyword_init: true)

      SETTINGS_SQL = <<~SQL
        WITH requested(name) AS (
          SELECT unnest(ARRAY[%<settings>s]::text[])
        )
        SELECT requested.name,
               current_setting(requested.name, true) AS setting,
               pg_settings.reset_val
          FROM requested
          LEFT JOIN pg_settings ON pg_settings.name = requested.name
         ORDER BY requested.name
      SQL

      ADVISORY_LOCKS_SQL = <<~SQL
        SELECT database::text,
               classid::text,
               objid::text,
               objsubid,
               mode
          FROM pg_locks
         WHERE locktype = 'advisory'
           AND pid = pg_backend_pid()
           AND granted
         ORDER BY database, classid, objid, objsubid, mode
      SQL

      def initialize(configuration)
        @configuration = configuration
        @allowed_settings = AllowedSettings.new(configuration.allowed_settings)
      end

      def establish_baseline(connection, state)
        snapshot = capture_with_timeout(connection, settings_for(state))
        state.capture_baseline(snapshot)
        snapshot
      end

      def inspect(connection, state, inspection_point:)
        baseline = state.baseline
        return establish_baseline(connection, state) unless baseline
        return unless state.dirty?

        snapshot = capture_with_timeout(connection, settings_for(state, baseline))
        report = build_report(baseline, snapshot, state, inspection_point)
        state.finish_inspection(
          snapshot: snapshot,
          rebaseline: report.leak? && @configuration.rebaseline_after_report
        )
        report if report.leak?
      end

      private

      def advisory_lock_changes(baseline, snapshot)
        baseline_fingerprints = baseline.advisory_locks.map(&:fingerprint)
        snapshot.advisory_locks.reject do |lock|
          baseline_fingerprints.include?(lock.fingerprint)
        end
      end

      def build_report(baseline, snapshot, state, inspection_point)
        Report.new(
          inspection_point: inspection_point,
          setting_changes: setting_changes(baseline, snapshot),
          advisory_locks: advisory_lock_changes(baseline, snapshot),
          suspicions: state.suspicions
        )
      end

      def capture_advisory_locks(connection)
        return [] unless @configuration.check_advisory_locks

        connection.select_all(ADVISORY_LOCKS_SQL, "PoolLint").map do |row|
          AdvisoryLock.new(
            database: row["database"],
            class_id: row["classid"],
            object_key: row["objid"],
            object_sub_id: row["objsubid"].to_i,
            mode: row["mode"]
          ).tap do |lock|
            lock.human_name = KannukiLockResolver.name_for(lock)
          end
        end
      end

      def capture_settings(connection, names)
        quoted_names = names.map { |name| connection.quote(name) }.join(", ")
        sql = format(SETTINGS_SQL, settings: quoted_names)
        connection.select_all(sql, "PoolLint").to_h do |row|
          [
            row.fetch("name"),
            SettingValue.new(setting: row["setting"], reset_value: row["reset_val"])
          ]
        end
      end

      def capture_snapshot(connection, names)
        Snapshot.new(
          settings: capture_settings(connection, names),
          advisory_locks: capture_advisory_locks(connection)
        )
      end

      def capture_with_timeout(connection, names)
        snapshot = nil
        timeout_ms = (@configuration.inspection_timeout * 1000).ceil
        ExecutionState.while_inspecting do
          connection.transaction(requires_new: true, joinable: false) do
            original_timeout = capture_statement_timeout(connection, names)
            connection.execute("SET LOCAL statement_timeout = #{timeout_ms}")
            snapshot = capture_snapshot(connection, names)
            restore_statement_timeout(snapshot, original_timeout)
            raise ActiveRecord::Rollback
          end
        end
        snapshot
      rescue StandardError => e
        raise InspectionTimeout, "inspection exceeded statement_timeout" if query_canceled?(e)

        raise
      end

      def capture_statement_timeout(connection, names)
        return unless names.include?("statement_timeout")

        connection.select_value("SELECT current_setting('statement_timeout')")
      end

      def comparison_for(name, baseline_value, current_value)
        return baseline_comparison(name, baseline_value, current_value) if baseline_value

        reset_comparison(name, current_value)
      end

      def baseline_comparison(name, baseline_value, current_value)
        return if baseline_value.setting == current_value.setting

        SettingChange.new(
          name: name,
          baseline: baseline_value.setting,
          current: current_value.setting,
          reset_value: current_value.reset_value,
          comparison: :baseline
        )
      end

      def reset_comparison(name, current_value)
        reset_value = current_value.reset_value
        reset_value = "" if reset_value.nil?
        return if current_value.setting.to_s == reset_value.to_s

        SettingChange.new(
          name: name,
          baseline: nil,
          current: current_value.setting,
          reset_value: reset_value,
          comparison: :reset_value
        )
      end

      def query_canceled?(error)
        active_record_timeout = defined?(ActiveRecord::QueryCanceled) &&
                                error.is_a?(ActiveRecord::QueryCanceled)
        active_record_timeout || error.cause&.class&.name == "PG::QueryCanceled"
      end

      def restore_statement_timeout(snapshot, original_timeout)
        return unless original_timeout

        captured = snapshot.settings.fetch("statement_timeout")
        snapshot.settings["statement_timeout"] = SettingValue.new(
          setting: original_timeout,
          reset_value: captured.reset_value
        )
      end

      def setting_changes(baseline, snapshot)
        names = baseline.settings.keys | snapshot.settings.keys
        names.filter_map do |name|
          current = snapshot.settings.fetch(name, SettingValue.new)
          change = comparison_for(name, baseline.settings[name], current)
          change unless change && @allowed_settings.allow?(name, change.current)
        end
      end

      def settings_for(state, baseline = nil)
        (
          SPECIAL_SETTINGS +
          @configuration.watched_settings +
          state.monitored_settings +
          Array(baseline&.settings&.keys)
        ).compact.map(&:downcase).uniq
      end
    end
  end
end
