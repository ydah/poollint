# frozen_string_literal: true

module PoolLint
  module Hooks
    CHECKOUT_CALLBACK = proc { |connection| CheckoutHook.call(connection) }
    CHECKIN_CALLBACK = proc { |connection| CheckinHook.call(connection) }

    class << self
      def install!
        return if @installed

        adapter = ActiveRecord::ConnectionAdapters::AbstractAdapter
        adapter.prepend(Lifecycle)
        adapter.descendants.each { |descendant| install_callbacks(descendant) }
        install_callbacks(adapter)
        @installed = true
      end

      private

      def install_callbacks(adapter)
        adapter.set_callback(:checkout, :before, CHECKOUT_CALLBACK)
        adapter.set_callback(:checkin, :before, CHECKIN_CALLBACK)
      end
    end
  end
end
