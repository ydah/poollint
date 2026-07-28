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

    def mark_dirty(kind:, setting:, sql:, call_site:, monitor_setting: true)
      @mutex.synchronize do
        @dirty = true
        @monitored_settings << setting if setting && monitor_setting
        @suspicions.add(
          Suspicion.new(
            kind: kind,
            setting: setting,
            sql: sql,
            call_site: call_site
          )
        )
      end
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
      @monitored_settings = Set.new
      @suspicions.clear
    end
  end
end
