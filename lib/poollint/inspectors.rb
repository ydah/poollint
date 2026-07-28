# frozen_string_literal: true

module PoolLint
  module Inspectors
    module_function

    def for(connection, configuration)
      return PostgreSQL.new(configuration) if connection.adapter_name == "PostgreSQL"

      nil
    end
  end
end
