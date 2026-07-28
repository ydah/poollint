# frozen_string_literal: true

module PoolLint
  Suspicion = Struct.new(
    :kind,
    :setting,
    :sql,
    :call_site,
    :lock_operation,
    :lock_name,
    keyword_init: true
  )

  class SuspicionLog
    SQL_LIMIT = 200

    def initialize(limit:)
      @limit = limit
      @entries = []
    end

    def add(suspicion)
      @entries.shift if @entries.length >= @limit
      @entries << normalized(suspicion)
    end

    def clear
      @entries.clear
    end

    def entries
      @entries.dup
    end

    private

    def normalized(suspicion)
      suspicion.dup.tap do |entry|
        entry.sql = entry.sql.to_s.slice(0, SQL_LIMIT)
      end
    end
  end
end
