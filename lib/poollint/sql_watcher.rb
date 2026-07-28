# frozen_string_literal: true

require "active_support/notifications"

module PoolLint
  class SqlWatcher
    Detection = Struct.new(
      :kind,
      :setting,
      :lock_operation,
      :lock_name,
      keyword_init: true
    )

    ADVISORY_PATTERN = /
      \bpg_(?:try_)?advisory_
      (?:lock(?:_shared)?|unlock(?:_shared|_all)?)\s*\(
    /ix
    LEADING_COMMENTS = %r{\A(?:\s+|/\*.*?\*/|--[^\n]*(?:\n|\z))*}m
    MYSQL_LOCK_OPERATIONS = {
      "GET_LOCK" => :acquire,
      "RELEASE_LOCK" => :release,
      "RELEASE_ALL_LOCKS" => :release_all
    }.freeze
    MYSQL_LOCK_PATTERN = /\b(GET_LOCK|RELEASE_LOCK|RELEASE_ALL_LOCKS)\s*\(/i
    SETTING_PATTERN = /\A[a-z_][a-z0-9_.-]*/i
    SPECIAL_SETTINGS = {
      "NAMES" => "client_encoding",
      "ROLE" => "role",
      "SCHEMA" => "search_path",
      "SESSION AUTHORIZATION" => "session_authorization",
      "TIME ZONE" => "timezone",
      "XML OPTION" => "xmloption"
    }.freeze

    class << self
      def install!
        return if @subscriber

        @subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          process(args.last)
        end
      end

      def process(payload)
        return if ExecutionState.inspecting?
        return if payload[:name] == "SCHEMA"

        connection = payload[:connection]
        detection = detect(payload[:sql])
        return unless connection && detection

        state_for(connection).mark_dirty(
          kind: detection.kind,
          setting: detection.setting,
          sql: payload[:sql],
          call_site: application_call_site,
          monitor_setting: PoolLint.configuration.track_custom_gucs,
          lock_operation: detection.lock_operation,
          lock_name: detection.lock_name
        )
      end

      def detect(sql)
        statement = sql.to_s.sub(LEADING_COMMENTS, "").strip
        return if statement.empty?
        return Detection.new(kind: :advisory_lock) if statement.match?(ADVISORY_PATTERN)

        detect_user_level_lock(statement) || detect_set(statement) || detect_reset(statement)
      end

      private

      def application_call_site
        location = caller_locations.find do |candidate|
          path = candidate.absolute_path || candidate.path
          path &&
            !path.include?("/lib/poollint/") &&
            !path.include?("/gems/") &&
            !path.include?("/active_support/")
        end
        return unless location

        "#{location.path}:#{location.lineno}"
      end

      def detect_reset(statement)
        match = statement.match(/\ARESET\s+(.+?)(?:\s*;)?\z/im)
        return unless match

        key = normalize_setting(match[1])
        Detection.new(kind: :reset, setting: key == "all" ? nil : key)
      end

      def detect_user_level_lock(statement)
        match = statement.match(MYSQL_LOCK_PATTERN)
        return unless match

        function = match[1].upcase
        Detection.new(
          kind: :user_level_lock,
          lock_operation: MYSQL_LOCK_OPERATIONS.fetch(function),
          lock_name: mysql_lock_name(statement, function)
        )
      end

      def state_for(connection)
        ConnectionState.fetch(
          connection,
          suspicion_limit: PoolLint.configuration.suspicion_limit
        )
      end

      def detect_set(statement)
        return if statement.match?(/\ASET\s+(?:LOCAL|TRANSACTION)\b/i)

        session_authorization = statement.match?(/\ASET\s+SESSION\s+AUTHORIZATION\b/i)
        return Detection.new(kind: :set, setting: "session_authorization") if session_authorization

        mysql_transaction = detect_mysql_session_transaction(statement)
        return mysql_transaction if mysql_transaction

        match = statement.match(/\ASET\s+(?:SESSION\s+)?(.+)\z/im)
        return unless match

        body = match[1].strip
        return if body.match?(/\A(?:CONSTRAINTS|TRANSACTION)\b/i)

        key = normalize_setting(body)
        Detection.new(kind: :set, setting: key)
      end

      def normalize_setting(body)
        normalized = body.to_s.strip.sub(/;\z/, "")
        normalized = normalized.sub(/\A@@(?:SESSION\.)?/i, "")
        normalized = normalized.upcase
        special = SPECIAL_SETTINGS.find { |name, _| normalized.start_with?(name) }
        return special.last if special

        normalized.downcase.match(SETTING_PATTERN)&.to_s
      end

      def mysql_lock_name(statement, function)
        return if function == "RELEASE_ALL_LOCKS"

        pattern = /\b#{function}\s*\(\s*(?:'((?:\\.|''|[^'])*)'|"((?:\\.|""|[^"])*)")/im
        match = statement.match(pattern)
        return unless match

        name = match[1]&.gsub("''", "'") || match[2]&.gsub('""', '"')
        name&.gsub(/\\(.)/, '\1')
      end

      def detect_mysql_session_transaction(statement)
        match = statement.match(/\ASET\s+SESSION\s+TRANSACTION\s+(.+)\z/im)
        return unless match

        setting = if match[1].match?(/\AISOLATION\s+LEVEL\b/i)
                    "transaction_isolation"
                  elsif match[1].match?(/\AREAD\s+(?:ONLY|WRITE)\b/i)
                    "transaction_read_only"
                  end
        Detection.new(kind: :set, setting: setting) if setting
      end
    end
  end
end
