# frozen_string_literal: true

RSpec.describe PoolLint::ConnectionState do
  subject(:state) { described_class.new(suspicion_limit: 2) }

  def mark(setting)
    state.mark_dirty(
      kind: :set,
      setting: setting,
      sql: "SET #{setting} = value",
      call_site: "example.rb:1"
    )
  end

  it "keeps dirty tracking and baseline together" do
    state.capture_baseline(:baseline)
    mark("search_path")

    expect(state).to be_dirty
    expect(state.baseline).to eq(:baseline)
    expect(state.monitored_settings).to eq(["search_path"])
  end

  it "bounds suspicion history as a ring buffer" do
    mark("one")
    mark("two")
    mark("three")

    expect(state.suspicions.map(&:setting)).to eq(%w[two three])
  end

  it "stores only the first 200 characters of suspicious SQL" do
    state.mark_dirty(kind: :set, setting: "x", sql: "x" * 250, call_site: nil)

    expect(state.suspicions.first.sql).to eq("x" * 200)
  end

  it "can record a setting without dynamically monitoring it" do
    state.mark_dirty(
      kind: :set,
      setting: "myapp.tenant",
      sql: "SET myapp.tenant = 1",
      call_site: nil,
      monitor_setting: false
    )

    expect(state.monitored_settings).to be_empty
    expect(state.suspicions.first.setting).to eq("myapp.tenant")
  end

  it "attaches only one state object to a connection" do
    connection = Object.new

    first = described_class.fetch(connection, suspicion_limit: 2)
    second = described_class.fetch(connection, suspicion_limit: 99)

    expect(second).to be(first)
  end

  it "can detect and restore lifecycle detachment" do
    connection = Object.new
    state = described_class.fetch(connection, suspicion_limit: 2)

    described_class.remove(connection)
    expect(described_class.attached?(connection, state)).to be(false)

    described_class.attach(connection, state)
    expect(described_class.attached?(connection, state)).to be(true)
  end
end
