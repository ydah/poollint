# frozen_string_literal: true

RSpec.describe PoolLint::Configuration do
  it "uses safe production defaults" do
    configuration = described_class.new(environment: "production")

    expect(configuration.inspection_point).to eq(:checkout)
    expect(configuration.mode).to eq(:log)
    expect(configuration.inspection_timeout_ms).to eq(250)
  end

  it "uses immediate test defaults" do
    configuration = described_class.new(environment: "test")

    expect(configuration.inspection_point).to eq(:checkin)
    expect(configuration.mode).to eq(:raise)
  end

  it "rejects an invalid probability" do
    configuration = described_class.new
    configuration.check_probability = 1.1

    expect { configuration.validate! }
      .to raise_error(ArgumentError, /check_probability/)
  end

  it "normalizes watched setting names" do
    configuration = described_class.new
    configuration.watched_settings = ["Search_Path", :ROLE, "role"]

    expect(configuration.validate!.watched_settings).to eq(%w[search_path role])
  end
end
