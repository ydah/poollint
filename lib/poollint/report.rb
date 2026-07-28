# frozen_string_literal: true

module PoolLint
  SettingChange = Struct.new(
    :name,
    :baseline,
    :current,
    :reset_value,
    :comparison,
    keyword_init: true
  )

  AdvisoryLock = Struct.new(
    :database,
    :class_id,
    :object_key,
    :object_sub_id,
    :mode,
    keyword_init: true
  ) do
    def fingerprint
      [database, class_id, object_key, object_sub_id, mode]
    end
  end

  class Report
    attr_reader :advisory_locks, :inspection_point, :setting_changes, :suspicions

    def initialize(inspection_point:, setting_changes:, advisory_locks:, suspicions:)
      @inspection_point = inspection_point
      @setting_changes = setting_changes
      @advisory_locks = advisory_locks
      @suspicions = suspicions
    end

    def leak?
      setting_changes.any? || advisory_locks.any?
    end

    def to_h
      {
        inspection_point: inspection_point,
        setting_changes: setting_changes.map(&:to_h),
        advisory_locks: advisory_locks.map(&:to_h),
        suspicions: suspicions.map(&:to_h)
      }
    end

    def to_s
      lines = ["PoolLint detected leaked PostgreSQL session state at #{inspection_point}."]
      append_setting_changes(lines)
      append_advisory_locks(lines)
      append_suspicions(lines)
      lines.join("\n")
    end

    private

    def append_advisory_locks(lines)
      return if advisory_locks.empty?

      lines << "Advisory locks still held:"
      advisory_locks.each do |lock|
        lines << "  #{lock.mode} (#{lock.class_id}, #{lock.object_key}, #{lock.object_sub_id})"
      end
    end

    def append_setting_changes(lines)
      return if setting_changes.empty?

      lines << "Changed settings:"
      setting_changes.each do |change|
        expected = change.comparison == :baseline ? change.baseline : change.reset_value
        lines << "  #{change.name}: expected #{expected.inspect}, got #{change.current.inspect}"
      end
    end

    def append_suspicions(lines)
      return if suspicions.empty?

      lines << "Suspicious statements:"
      suspicions.each do |suspicion|
        location = suspicion.call_site ? " (#{suspicion.call_site})" : ""
        lines << "  #{suspicion.sql.to_s.strip}#{location}"
      end
    end
  end
end
