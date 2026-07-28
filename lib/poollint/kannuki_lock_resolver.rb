# frozen_string_literal: true

module PoolLint
  module KannukiLockResolver
    module_function

    def name_for(lock)
      return unless defined?(::Kannuki::LockKey) && defined?(::Kannuki::LockManager)

      ::Kannuki::LockManager.current_locks.find do |name|
        ::Kannuki::LockKey.new(name).numeric_key == lock.numeric_key
      end
    rescue StandardError
      nil
    end
  end
end
