# frozen_string_literal: true

RSpec.describe PoolLint::ExecutionState do
  describe ".while_inspecting" do
    it "sets and restores the inspection flag" do
      expect(described_class.inspecting?).to be(false)

      described_class.while_inspecting do
        expect(described_class.inspecting?).to be(true)
      end

      expect(described_class.inspecting?).to be(false)
    end

    it "restores the inspection flag after an exception" do
      expect do
        described_class.while_inspecting { raise "failure" }
      end.to raise_error("failure")

      expect(described_class.inspecting?).to be(false)
    end
  end

  describe ".suppress" do
    it "scopes suppression to the block" do
      described_class.suppress do
        expect(described_class.suppressed?).to be(true)
      end

      expect(described_class.suppressed?).to be(false)
    end
  end
end
