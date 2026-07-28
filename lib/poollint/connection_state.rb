# frozen_string_literal: true

require "set"
require "thread"

module PoolLint
  class ConnectionState
    IVAR = :@poollint_state

    def self.attach(connection, state)
      connection.instance_variable_set(IVAR, state)
    end

    def self.attached?(connection, state)
      connection.instance_variable_get(IVAR).equal?(state)
    end

    def self.fetch(connection, suspicion_limit:)
      connection.instance_variable_get(IVAR) ||
        attach(connection, new(suspicion_limit: suspicion_limit))
    end

    def self.remove(connection)
      connection.remove_instance_variable(IVAR) if connection.instance_variable_defined?(IVAR)
    end

    def initialize(suspicion_limit:)
      @mutex = Mutex.new
      @suspicions = SuspicionLog.new(limit: suspicion_limit)
      reset!
    end

    def baseline?
      @mutex.synchronize { !@baseline.nil? }
    end

    def baseline
      @mutex.synchronize { @baseline }
    end

    def capture_baseline(snapshot)
      @mutex.synchronize do
        @baseline = snapshot
        clear_tracking
      end
    end

    def dirty?
      @mutex.synchronize { @dirty }
    end

    def mark_dirty(kind:, setting:, sql:, call_site:, **tracking)
      @mutex.synchronize do
        @dirty = true
        @monitored_settings << setting if setting && tracking.fetch(:monitor_setting, true)
        track_user_lock(tracking[:lock_operation], tracking[:lock_name])
        @suspicions.add(
          Suspicion.new(
            kind: kind,
            setting: setting,
            sql: sql,
            call_site: call_site,
            lock_operation: tracking[:lock_operation],
            lock_name: tracking[:lock_name]
          )
        )
      end
    end

    def inferred_user_locks
      @mutex.synchronize { @inferred_user_locks.dup }
    end

    def monitored_settings
      @mutex.synchronize { @monitored_settings.to_a }
    end

    def reset!
      @mutex.synchronize do
        @baseline = nil
        clear_tracking
      end
    end

    def suspicions
      @mutex.synchronize { @suspicions.entries }
    end

    def finish_inspection(snapshot:, rebaseline:)
      @mutex.synchronize do
        @baseline = snapshot if rebaseline
        clear_tracking
      end
    end

    private

    def clear_tracking
      @dirty = false
      @inferred_user_locks = {}
      @monitored_settings = Set.new
      @suspicions.clear
    end

    def track_user_lock(operation, name)
      case operation
      when :acquire
        key = name || "<dynamic>"
        @inferred_user_locks[key] = @inferred_user_locks.fetch(key, 0) + 1
      when :release
        release_user_lock(name)
      when :release_all
        @inferred_user_locks.clear
      end
    end

    def release_user_lock(name)
      return unless name && @inferred_user_locks.key?(name)

      remaining = @inferred_user_locks.fetch(name) - 1
      if remaining.positive?
        @inferred_user_locks[name] = remaining
      else
        @inferred_user_locks.delete(name)
      end
    end
  end
end
