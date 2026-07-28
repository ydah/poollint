# frozen_string_literal: true

RSpec.describe PoolLint::AllowedSettings do
  subject(:allowed) do
    described_class.new(
      "search_path" => %w[public tenant],
      role: /reporting/,
      "statement_timeout" => ->(value) { value.to_i <= 500 }
    )
  end

  it "matches arrays, regular expressions, and callables" do
    expect(allowed.allow?("search_path", "tenant")).to be(true)
    expect(allowed.allow?("role", "reporting_user")).to be(true)
    expect(allowed.allow?("statement_timeout", "250")).to be(true)
  end

  it "rejects an unconfigured value" do
    expect(allowed.allow?("search_path", "private")).to be(false)
  end

  it "allows every value for names configured as an array" do
    allowed_settings = described_class.new(%w[statement_timeout])

    expect(allowed_settings.allow?("statement_timeout", "10s")).to be(true)
    expect(allowed_settings.allow?("search_path", "private")).to be(false)
  end
end
