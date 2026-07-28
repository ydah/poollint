# frozen_string_literal: true

RSpec.describe PoolLint::InspectionRunner do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_double(Logger, warn: nil)
  end

  it "converts inspector failures to warnings" do
    connection = Struct.new(:adapter_name).new("PostgreSQL")
    inspector = instance_double(PoolLint::Inspectors::PostgreSQL)
    allow(PoolLint::Inspectors::PostgreSQL).to receive(:new).and_return(inspector)
    allow(inspector).to receive(:establish_baseline).and_raise("database unavailable")

    expect { described_class.call(connection, :checkout) }.not_to raise_error
    expect(PoolLint.configuration.logger).to have_received(:warn)
      .with(/inspection skipped.*database unavailable/)
  end

  [
    PoolLint::InspectionTimeout.new("too slow"),
    ActiveRecord::ConnectionNotEstablished.new("disconnected"),
    KeyError.new("invalid inspector response")
  ].each do |failure|
    it "keeps pool callbacks usable after #{failure.class}" do
      connection = Struct.new(:adapter_name).new("PostgreSQL")
      inspector = instance_double(PoolLint::Inspectors::PostgreSQL)
      allow(PoolLint::Inspectors::PostgreSQL).to receive(:new).and_return(inspector)
      allow(inspector).to receive(:establish_baseline).and_raise(failure)

      expect { described_class.call(connection, :checkout) }.not_to raise_error
      expect(PoolLint.configuration.logger).to have_received(:warn)
    end
  end

  it "does not run a dirty inspection when probability excludes it" do
    connection = Struct.new(:adapter_name).new("PostgreSQL")
    state = PoolLint.connection_state(connection)
    state.capture_baseline(:baseline)
    state.mark_dirty(kind: :set, setting: "role", sql: "SET ROLE x", call_site: nil)
    PoolLint.configuration.check_probability = 0.0
    inspector = instance_spy(PoolLint::Inspectors::PostgreSQL)
    allow(PoolLint::Inspectors::PostgreSQL).to receive(:new).and_return(inspector)

    described_class.call(connection, :checkout)
    expect(inspector).not_to have_received(:inspect)
  end

  it "does not attach state or execute SQL for unsupported adapters" do
    connection = Struct.new(:adapter_name).new("SQLite")
    allow(PoolLint::ConnectionState).to receive(:fetch)

    described_class.call(connection, :checkout)

    expect(PoolLint::ConnectionState).not_to have_received(:fetch)
  end
end
