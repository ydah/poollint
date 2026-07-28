# frozen_string_literal: true

require "active_support/isolated_execution_state"

module PoolLint
  module ExecutionState
    KEY = :poollint_inspecting
    SUPPRESSION_KEY = :poollint_suppressed

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

    def suppressed?
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY] == true
    end

    def suppress
      previous = ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY]
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[SUPPRESSION_KEY] = previous
    end
  end
end
