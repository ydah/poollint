# frozen_string_literal: true

module PoolLint
  module Hooks
    module CheckoutHook
      module_function

      def call(connection)
        InspectionRunner.call(connection, :checkout)
      end
    end
  end
end
