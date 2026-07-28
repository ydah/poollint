# frozen_string_literal: true

require "poollint/railtie"

RSpec.describe PoolLint::Railtie do
  it "registers automatic installation during Rails boot" do
    names = described_class.initializers.map(&:name)

    expect(names).to include("poollint.install")
  end
end
