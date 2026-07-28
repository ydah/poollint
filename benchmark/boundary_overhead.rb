# frozen_string_literal: true

require "bundler/setup"
require "benchmark/ips"
require "poollint"

PoolLint.reset_configuration!(environment: "production")

connection = Object.new
state = PoolLint.connection_state(connection)
state.capture_baseline(Object.new)

warmup = Integer(ENV.fetch("BENCHMARK_WARMUP", "1"))
time = Integer(ENV.fetch("BENCHMARK_TIME", "3"))

Benchmark.ips do |benchmark|
  benchmark.config(time: time, warmup: warmup)
  benchmark.report("empty boundary") { nil }
  benchmark.report("non-dirty guard") do
    PoolLint::InspectionRunner.call(connection, :checkout)
  end
  benchmark.compare!
end
