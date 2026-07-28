# frozen_string_literal: true

RSpec.describe PoolLint::KannukiLockResolver do
  let(:lock) do
    PoolLint::AdvisoryLock.new(
      class_id: "0",
      object_key: "42",
      object_sub_id: 1,
      mode: "ExclusiveLock"
    )
  end

  it "returns no name when Kannuki is not loaded" do
    hide_const("Kannuki") if defined?(Kannuki)

    expect(described_class.name_for(lock)).to be_nil
  end

  it "resolves a loaded Kannuki lock key without a runtime dependency" do
    lock_key = Struct.new(:numeric_key)
    lock_key_class = Class.new do
      define_singleton_method(:new) { |_name| lock_key.new(42) }
    end
    lock_manager = Class.new do
      define_singleton_method(:current_locks) { ["orders/42"] }
    end
    stub_const("Kannuki::LockKey", lock_key_class)
    stub_const("Kannuki::LockManager", lock_manager)

    expect(described_class.name_for(lock)).to eq("orders/42")
  end
end
