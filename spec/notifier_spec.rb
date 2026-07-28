# frozen_string_literal: true

RSpec.describe PoolLint::Notifier do
  subject(:notifier) { described_class.new(PoolLint.configuration) }

  let(:report) do
    PoolLint::Report.new(
      inspection_point: :checkout,
      setting_changes: [
        PoolLint::SettingChange.new(
          name: "search_path",
          baseline: "\"$user\", public",
          current: "private",
          reset_value: "\"$user\", public",
          comparison: :baseline
        )
      ],
      advisory_locks: [],
      suspicions: []
    )
  end

  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_double(Logger, warn: nil)
  end

  it "instruments and logs a report" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(described_class::EVENT_NAME) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    notifier.call(report)

    expect(described_class::EVENT_NAME).to eq("leaked_state.poollint")
    expect(events.first.payload[:inspection_point]).to eq(:checkout)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "raises LeakDetected in raise mode" do
    PoolLint.configuration.mode = :raise

    expect { notifier.call(report) }
      .to raise_error(PoolLint::LeakDetected, /search_path/)
  end

  it "uses the public leaked-session-state exception name" do
    PoolLint.configuration.mode = :raise

    expect { notifier.call(report) }
      .to raise_error(PoolLint::LeakedSessionState, /handed out/)
  end

  it "honors suppress and ignore_if" do
    PoolLint.configuration.ignore_if = ->(_report) { true }

    expect { PoolLint.suppress { notifier.call(report) } }.not_to raise_error
    expect(PoolLint.configuration.logger).not_to have_received(:warn)
  end
end
