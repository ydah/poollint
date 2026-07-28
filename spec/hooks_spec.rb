# frozen_string_literal: true

RSpec.describe PoolLint::Hooks do
  it "installs checkout after and checkin before callbacks exactly once" do
    described_class.install!
    described_class.install!
    adapter = ActiveRecord::ConnectionAdapters::AbstractAdapter

    checkout_callbacks = adapter._checkout_callbacks.select do |callback|
      callback.filter.equal?(described_class::CHECKOUT_CALLBACK)
    end
    checkin_callbacks = adapter._checkin_callbacks.select do |callback|
      callback.filter.equal?(described_class::CHECKIN_CALLBACK)
    end

    expect(checkout_callbacks.map(&:kind)).to eq([:after])
    expect(checkin_callbacks.map(&:kind)).to eq([:before])
  end
end
