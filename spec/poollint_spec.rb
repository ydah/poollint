# frozen_string_literal: true

RSpec.describe PoolLint do
  it "has a version number" do
    expect(PoolLint::VERSION).not_to be_nil
  end

  it "warns when checkin inspection is selected outside test" do
    described_class.reset_configuration!(environment: "production")
    described_class.configuration.inspection_point = :checkin
    described_class.configuration.logger = instance_spy(Logger)

    described_class.install!

    expect(described_class.configuration.logger).to have_received(:warn)
      .with(/pool mutex/)
  ensure
    described_class.reset_configuration!(environment: "production")
  end

  it "does not propagate logger failures into pool callbacks" do
    described_class.reset_configuration!(environment: "production")
    logger = instance_double(Logger)
    allow(logger).to receive(:warn).and_raise("logger unavailable")
    described_class.configuration.logger = logger
    allow(Kernel).to receive(:warn)

    expect { described_class.log_warning("inspection failed") }.not_to raise_error
  ensure
    described_class.reset_configuration!(environment: "production")
  end
end
