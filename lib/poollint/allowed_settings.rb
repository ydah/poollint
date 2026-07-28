# frozen_string_literal: true

module PoolLint
  class AllowedSettings
    UNCONFIGURED = Object.new.freeze

    def initialize(rules)
      @rules = rules
    end

    def allow?(name, value)
      rule = @rules.fetch(name) { @rules.fetch(name.to_sym, UNCONFIGURED) }

      case rule
      when UNCONFIGURED then false
      when nil, true then true
      when Proc then rule.call(value)
      when Regexp then rule.match?(value.to_s)
      when Array then rule.include?(value)
      else rule == value
      end
    end
  end
end
