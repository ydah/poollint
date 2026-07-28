# frozen_string_literal: true

module PoolLint
  module Hooks
    module CheckinHook
      module_function

      # Active Record invokes this while holding the pool mutex. This inspection
      # point is intended for tests and controlled environments, not production.
      def call(connection)
        InspectionRunner.call(connection, :checkin)
      end
    end
  end
end
