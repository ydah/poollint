# frozen_string_literal: true

module PoolLint
  class Error < StandardError; end

  class InspectionTimeout < Error; end

  class LeakedSessionState < Error
    attr_reader :report

    def initialize(report)
      @report = report
      super(report.to_s)
    end
  end

  LeakDetected = LeakedSessionState
end
