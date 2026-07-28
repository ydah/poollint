# frozen_string_literal: true

module PoolLint
  DEFAULT_PG_SETTINGS = %w[
    role
    session_authorization
    search_path
    statement_timeout
    lock_timeout
    idle_in_transaction_session_timeout
    default_transaction_read_only
  ].freeze
  DEFAULT_MYSQL_SETTINGS = %w[
    sql_mode
    time_zone
    transaction_isolation
    transaction_read_only
    lock_wait_timeout
    max_execution_time
  ].freeze

  class Configuration
    INSPECTION_POINTS = %i[checkout checkin].freeze
    MODES = %i[log raise].freeze

    attr_reader :environment
    attr_accessor :allowed_settings,
                  :check_advisory_locks,
                  :check_probability,
                  :ignore_if,
                  :inspection_point,
                  :inspection_timeout,
                  :logger,
                  :mode,
                  :mysql_watched_settings,
                  :rebaseline_after_report,
                  :suspicion_log_size,
                  :track_custom_gucs,
                  :watched_settings

    def initialize(environment: nil)
      @environment = environment || default_environment
      test_environment = @environment.to_s == "test"
      @allowed_settings = []
      @check_advisory_locks = true
      @check_probability = 1.0
      @ignore_if = nil
      @inspection_point = test_environment ? :checkin : :checkout
      @inspection_timeout = 0.25
      @logger = nil
      @mode = test_environment ? :raise : :log
      @mysql_watched_settings = DEFAULT_MYSQL_SETTINGS.dup
      @rebaseline_after_report = true
      @suspicion_log_size = 20
      @track_custom_gucs = true
      @watched_settings = DEFAULT_PG_SETTINGS.dup
    end

    def inspection_timeout_ms
      (inspection_timeout * 1000).round
    end

    def inspection_timeout_ms=(value)
      self.inspection_timeout = Float(value) / 1000
    end

    def suspicion_limit
      suspicion_log_size
    end

    def suspicion_limit=(value)
      self.suspicion_log_size = value
    end

    def test_environment?
      environment.to_s == "test"
    end

    def validate!
      validate_choices!
      validate_flags!
      validate_probability!
      validate_positive_number!(:inspection_timeout, inspection_timeout)
      validate_positive_integer!(:suspicion_log_size, suspicion_log_size)
      validate_ignore_if!
      validate_allowed_settings!
      self.watched_settings = Array(watched_settings).map { |name| normalize_setting(name) }.uniq
      self.mysql_watched_settings = normalize_mysql_settings
      self
    end

    private

    def default_environment
      return Rails.env.to_s if defined?(Rails) && Rails.respond_to?(:env)

      ENV.fetch("RAILS_ENV", ENV.fetch("RACK_ENV", nil))
    end

    def normalize_setting(name)
      name.to_s.downcase
    end

    def normalize_mysql_settings
      Array(mysql_watched_settings).map do |name|
        normalized = normalize_setting(name)
        unless normalized.match?(/\A[a-z_][a-z0-9_]*\z/)
          raise ArgumentError, "invalid MySQL session variable: #{name}"
        end

        normalized
      end.uniq
    end

    def validate_allowed_settings!
      return if allowed_settings.is_a?(Array) || allowed_settings.is_a?(Hash)

      raise ArgumentError, "allowed_settings must be an Array or Hash"
    end

    def validate_boolean!(name, value)
      return if [true, false].include?(value)

      raise ArgumentError, "#{name} must be true or false"
    end

    def validate_choices!
      validate_member!(:inspection_point, inspection_point, INSPECTION_POINTS)
      validate_member!(:mode, mode, MODES)
    end

    def validate_flags!
      validate_boolean!(:check_advisory_locks, check_advisory_locks)
      validate_boolean!(:rebaseline_after_report, rebaseline_after_report)
      validate_boolean!(:track_custom_gucs, track_custom_gucs)
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

    def validate_positive_number!(name, value)
      return if value.is_a?(Numeric) && value.positive?

      raise ArgumentError, "#{name} must be a positive number"
    end

    def validate_probability!
      valid = check_probability.is_a?(Numeric) && check_probability.between?(0.0, 1.0)
      return if valid

      raise ArgumentError, "check_probability must be between 0.0 and 1.0"
    end
  end
end
