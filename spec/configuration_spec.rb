# frozen_string_literal: true

RSpec.describe PoolLint::Configuration do
  it "uses safe production defaults" do
    configuration = described_class.new(environment: "production")

    expect(configuration).to have_attributes(
      inspection_point: :checkout,
      mode: :log,
      inspection_timeout: 0.25
    )
    expect(configuration.watched_settings).to eq(PoolLint::DEFAULT_PG_SETTINGS)
    expect(configuration).to have_attributes(track_custom_gucs: true, check_advisory_locks: true)
  end

  it "uses immediate test defaults" do
    configuration = described_class.new(environment: "test")

    expect(configuration.inspection_point).to eq(:checkin)
    expect(configuration.mode).to eq(:raise)
    expect(configuration).to be_test_environment
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

  it "keeps millisecond and suspicion limit compatibility accessors" do
    configuration = described_class.new
    configuration.inspection_timeout_ms = 125
    configuration.suspicion_limit = 5

    expect(configuration.inspection_timeout).to eq(0.125)
    expect(configuration.suspicion_log_size).to eq(5)
  end

  it "accepts setting names or value rules for allowed settings" do
    array_configuration = described_class.new
    array_configuration.allowed_settings = ["statement_timeout"]
    hash_configuration = described_class.new
    hash_configuration.allowed_settings = { "application_name" => /worker/ }

    expect(array_configuration.validate!).to be(array_configuration)
    expect(hash_configuration.validate!).to be(hash_configuration)
  end
end
