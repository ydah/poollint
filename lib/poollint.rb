# frozen_string_literal: true

require_relative "poollint/version"
require_relative "poollint/errors"
require_relative "poollint/execution_state"
require_relative "poollint/configuration"
require_relative "poollint/suspicion_log"
require_relative "poollint/connection_state"
require_relative "poollint/sql_watcher"
require_relative "poollint/report"
require_relative "poollint/allowed_settings"
require_relative "poollint/kannuki_lock_resolver"
require_relative "poollint/inspectors/postgresql"
require_relative "poollint/inspectors"
require_relative "poollint/notifier"
require_relative "poollint/inspection_runner"
require_relative "poollint/hooks/checkout_hook"
require_relative "poollint/hooks/checkin_hook"
require_relative "poollint/hooks/lifecycle"
require_relative "poollint/hooks"

module PoolLint
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
      configuration.validate!
    end

    def connection_state(connection)
      ConnectionState.fetch(
        connection,
        suspicion_limit: configuration.suspicion_limit
      )
    end

    def install!
      require "active_record"

      SqlWatcher.install!
      Hooks.install!
      warn_about_checkin_in_production
    end

    def log_warning(message)
      logger = configuration.logger
      logger ||= ActiveRecord::Base.logger if defined?(ActiveRecord::Base)
      formatted = "[PoolLint] #{message}"
      return warn_with_logger(logger, formatted) if logger

      Kernel.warn(formatted)
    rescue StandardError
      nil
    end

    def reset_configuration!(environment: nil)
      @configuration = Configuration.new(environment: environment)
    end

    def suppress(&)
      ExecutionState.suppress(&)
    end

    private

    def warn_with_logger(logger, message)
      logger.warn(message)
    rescue StandardError => e
      Kernel.warn("#{message} (logger failed: #{e.class}: #{e.message})")
    end

    def warn_about_checkin_in_production
      return unless configuration.inspection_point == :checkin
      return if configuration.test_environment?

      log_warning(
        ":checkin inspection runs while the Active Record pool mutex is held; " \
        "use :checkout in production"
      )
    end
  end
end

require_relative "poollint/railtie" if defined?(Rails::Railtie)
