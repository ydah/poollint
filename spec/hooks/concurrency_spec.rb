# frozen_string_literal: true

RSpec.describe PoolLint::Hooks, :postgresql do
  before do
    PoolLint.reset_configuration!(environment: "production")
    PoolLint.configuration.logger = instance_spy(Logger)
    PoolLint.install!
  end

  it "keeps dirty tracking isolated across five concurrent connections" do
    pool = PoolLintPostgreSQLRecord.connection_pool
    ready = Queue.new
    release = Queue.new

    threads = 5.times.map do |index|
      Thread.new do
        connection = pool.checkout
        reset_postgresql_session(connection)
        connection.execute("SET myapp.thread_id = '#{index}'")
        state = PoolLint.connection_state(connection)
        ready << [connection.object_id, state.object_id, state.dirty?]
        release.pop
        reset_postgresql_session(connection)
        PoolLint::ConnectionState.remove(connection)
        pool.checkin(connection)
      end
    end

    results = 5.times.map { ready.pop }
    5.times { release << true }
    threads.each(&:join)

    expect(results.map(&:first).uniq.length).to eq(5)
    expect(results.map { |result| result[1] }.uniq.length).to eq(5)
    expect(results).to all(satisfy { |result| result[2] })
  end
end
