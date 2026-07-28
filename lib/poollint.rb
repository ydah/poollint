# frozen_string_literal: true

require_relative "poollint/version"
require_relative "poollint/execution_state"
require_relative "poollint/configuration"
require_relative "poollint/suspicion_log"
require_relative "poollint/connection_state"
require_relative "poollint/sql_watcher"

module PoolLint
  class Error < StandardError; end

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

    def reset_configuration!(environment: nil)
      @configuration = Configuration.new(environment: environment)
    end

    def suppress(&)
      ExecutionState.suppress(&)
    end
  end
end
