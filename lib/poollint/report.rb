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
    :human_name,
    keyword_init: true
  ) do
    def fingerprint
      [database, class_id, object_key, object_sub_id, mode]
    end

    def numeric_key
      (class_id.to_i << 32) | object_key.to_i
    end
  end

  UserLevelLock = Struct.new(
    :name,
    :acquisition_count,
    :mode,
    :status,
    :confidence,
    keyword_init: true
  ) do
    def fingerprint
      [name, mode, status]
    end
  end

  class Report
    attr_reader :advisory_locks,
                :inspection_point,
                :setting_changes,
                :suspicions,
                :user_level_locks

    def initialize(
      inspection_point:,
      setting_changes:,
      advisory_locks:,
      suspicions:,
      user_level_locks: []
    )
      @inspection_point = inspection_point
      @setting_changes = setting_changes
      @advisory_locks = advisory_locks
      @suspicions = suspicions
      @user_level_locks = user_level_locks
    end

    def leak?
      setting_changes.any? || advisory_locks.any? || user_level_locks.any?
    end

    def to_h
      {
        inspection_point: inspection_point,
        setting_changes: setting_changes.map(&:to_h),
        advisory_locks: advisory_locks.map(&:to_h),
        user_level_locks: user_level_locks.map(&:to_h),
        suspicions: suspicions.map(&:to_h)
      }
    end

    def to_s
      lines = [
        "PoolLint::LeakedSessionState",
        "",
        boundary_message
      ]
      append_setting_changes(lines)
      append_advisory_locks(lines)
      append_user_level_locks(lines)
      append_suspicions(lines)
      append_remediation(lines)
      lines.join("\n")
    end

    private

    def append_advisory_locks(lines)
      advisory_locks.each do |lock|
        lines << ""
        lines << "Leaked advisory lock:"
        lines << "  name: #{lock.human_name}" if lock.human_name
        lines << "  key: (classid=#{lock.class_id}, objid=#{lock.object_key}, mode=#{lock.mode})"
        location = latest_suspicion(kind: :advisory_lock)&.call_site
        lines << "  acquired at: #{location}" if location
      end
    end

    def append_setting_changes(lines)
      setting_changes.each do |change|
        expected = change.comparison == :baseline ? change.baseline : change.reset_value
        lines << ""
        lines << "Changed session setting:"
        lines << "  #{change.name}"
        lines << "  expected: #{expected.inspect}"
        lines << "  actual:   #{change.current.inspect}"
        location = latest_suspicion(setting: change.name)&.call_site
        lines << "  last SET at: #{location}" if location
      end
    end

    def append_user_level_locks(lines)
      user_level_locks.each do |lock|
        lines << ""
        lines << "Leaked MySQL user-level lock:"
        lines << "  name: #{lock.name}"
        lines << "  confidence: #{lock.confidence}"
        lines << "  acquisition count: #{lock.acquisition_count}" if lock.acquisition_count
        lines << "  status: #{lock.status}" if lock.status
        location = latest_suspicion(kind: :user_level_lock, lock_name: lock.name)&.call_site
        lines << "  acquired at: #{location}" if location
      end
    end

    def append_suspicions(lines)
      return if suspicions.empty?

      lines << ""
      lines << "Suspicious statements:"
      suspicions.each do |suspicion|
        location = suspicion.call_site ? " (#{suspicion.call_site})" : ""
        lines << "  #{suspicion.sql.to_s.strip}#{location}"
      end
    end

    def append_remediation(lines)
      lines << ""
      lines << "Reset the state before releasing the connection"
      lines << "(for example, RESET ROLE / RESET search_path / pg_advisory_unlock_all() /"
      lines << "RELEASE_ALL_LOCKS()),"
      lines << "or ensure cleanup runs in an ensure block."
    end

    def boundary_message
      if inspection_point == :checkin
        return "Connection was returned to the pool with modified session state."
      end

      "Connection was handed out with session state left over\nfrom a previous owner."
    end

    def latest_suspicion(kind: nil, setting: nil, lock_name: nil)
      suspicions.reverse.find do |suspicion|
        (!kind || suspicion.kind == kind) &&
          (!setting || suspicion.setting == setting) &&
          (!lock_name || suspicion.lock_name == lock_name)
      end
    end
  end
end
