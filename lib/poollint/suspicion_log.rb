# frozen_string_literal: true

module PoolLint
  Suspicion = Struct.new(
    :kind,
    :setting,
    :sql,
    :call_site,
    keyword_init: true
  )

  class SuspicionLog
    def initialize(limit:)
      @limit = limit
      @entries = []
    end

    def add(suspicion)
      @entries.shift if @entries.length >= @limit
      @entries << suspicion
    end

    def clear
      @entries.clear
    end

    def entries
      @entries.dup
    end
  end
end
