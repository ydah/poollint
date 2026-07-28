# frozen_string_literal: true

module PoolLint
  module Hooks
    module Lifecycle
      def discard!
        ConnectionState.remove(self)
        super
      end

      def reconnect!(...)
        super.tap { ConnectionState.remove(self) }
      end
    end
  end
end
