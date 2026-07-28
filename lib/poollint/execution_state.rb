# frozen_string_literal: true

require "active_support/isolated_execution_state"

module PoolLint
  module ExecutionState
    KEY = :poollint_inspecting

    module_function

    def inspecting?
      ActiveSupport::IsolatedExecutionState[KEY] == true
    end

    def while_inspecting
      previous = ActiveSupport::IsolatedExecutionState[KEY]
      ActiveSupport::IsolatedExecutionState[KEY] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = previous
    end
  end
end
