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

  it "attaches only one state object to a connection" do
    connection = Object.new

    first = described_class.fetch(connection, suspicion_limit: 2)
    second = described_class.fetch(connection, suspicion_limit: 99)

    expect(second).to be(first)
  end
end
