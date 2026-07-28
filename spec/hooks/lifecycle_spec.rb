# frozen_string_literal: true

RSpec.describe PoolLint::Hooks::Lifecycle do
  let(:connection_class) do
    Class.new do
      def discard!
        :discarded
      end

      def reconnect!
        :reconnected
      end

      prepend PoolLint::Hooks::Lifecycle
    end
  end

  it "drops the baseline after reconnect" do
    connection = connection_class.new
    original = PoolLint.connection_state(connection)
    original.capture_baseline(:baseline)

    expect(connection.reconnect!).to eq(:reconnected)
    expect(PoolLint.connection_state(connection)).not_to be(original)
  end

  it "removes all attached state on discard" do
    connection = connection_class.new
    original = PoolLint.connection_state(connection)

    expect(connection.discard!).to eq(:discarded)
    expect(PoolLint.connection_state(connection)).not_to be(original)
  end
end
