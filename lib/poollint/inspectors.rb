# frozen_string_literal: true

module PoolLint
  module Inspectors
    module_function

    def for(connection)
      return PostgreSQL if connection.adapter_name == "PostgreSQL"

      nil
    end
  end
end
