# frozen_string_literal: true

require "active_support/notifications"

module PoolLint
  class Notifier
    EVENT_NAME = "leaked_state.poollint"

    def initialize(configuration)
      @configuration = configuration
    end

    def call(report)
      return if ExecutionState.suppressed?
      return if @configuration.ignore_if&.call(report)

      ActiveSupport::Notifications.instrument(EVENT_NAME, report.to_h)

      raise LeakedSessionState, report if @configuration.mode == :raise

      PoolLint.log_warning(report.to_s)
    end
  end
end
