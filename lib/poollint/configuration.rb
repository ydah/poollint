# frozen_string_literal: true

module PoolLint
  class Configuration
    INSPECTION_POINTS = %i[checkout checkin].freeze
    MODES = %i[log raise].freeze

    attr_accessor :allowed_settings,
                  :check_probability,
                  :ignore_if,
                  :inspection_point,
                  :inspection_timeout_ms,
                  :logger,
                  :mode,
                  :rebaseline_after_report,
                  :suspicion_limit,
                  :watched_settings

    def initialize(environment: nil)
      environment ||= default_environment
      test_environment = environment.to_s == "test"
      @allowed_settings = {}
      @check_probability = 1.0
      @ignore_if = nil
      @inspection_point = test_environment ? :checkin : :checkout
      @inspection_timeout_ms = 250
      @logger = nil
      @mode = test_environment ? :raise : :log
      @rebaseline_after_report = true
      @suspicion_limit = 20
      @watched_settings = []
    end

    def validate!
      validate_member!(:inspection_point, inspection_point, INSPECTION_POINTS)
      validate_member!(:mode, mode, MODES)
      validate_probability!
      validate_positive_integer!(:inspection_timeout_ms, inspection_timeout_ms)
      validate_positive_integer!(:suspicion_limit, suspicion_limit)
      validate_ignore_if!
      validate_allowed_settings!
      self.watched_settings = Array(watched_settings).map { |name| normalize_setting(name) }.uniq
      self
    end

    private

    def default_environment
      ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", nil))
    end

    def normalize_setting(name)
      name.to_s.downcase
    end

    def validate_allowed_settings!
      return if allowed_settings.is_a?(Hash)

      raise ArgumentError, "allowed_settings must be a Hash"
    end

    def validate_ignore_if!
      return if ignore_if.nil? || ignore_if.respond_to?(:call)

      raise ArgumentError, "ignore_if must be callable"
    end

    def validate_member!(name, value, allowed)
      return if allowed.include?(value)

      choices = allowed.join(", ")
      raise ArgumentError, "#{name} must be one of: #{choices}"
    end

    def validate_positive_integer!(name, value)
      return if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive Integer"
    end

    def validate_probability!
      valid = check_probability.is_a?(Numeric) && check_probability.between?(0.0, 1.0)
      return if valid

      raise ArgumentError, "check_probability must be between 0.0 and 1.0"
    end
  end
end
