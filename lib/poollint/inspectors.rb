# frozen_string_literal: true

module PoolLint
  module Inspectors
    MYSQL_ADAPTERS = %w[Mysql2 Trilogy].freeze

    module_function

    def for(connection)
      return PostgreSQL if connection.adapter_name == "PostgreSQL"
      return MySQL if MYSQL_ADAPTERS.include?(connection.adapter_name)

      nil
    end
  end
end
