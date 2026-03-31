require 'typhoeus'
require 'faraday'
require 'faraday/typhoeus'
require_relative 'lib/tls_server'

# Validate thread safety of Typhoeus/libcurl connection pooling under
# Sidekiq-like concurrency. 25 threads sharing HTTP clients, each making
# sequential requests to a local TLS server.

THREADS = Integer(ENV.fetch('THREADS', 25))
REQUESTS_PER_THREAD = Integer(ENV.fetch('REQUESTS', 20))
EXPECTED_BODY = '{"status":"ok"}'

info = TLSServer.start
url = info.url
ca_path = info.ca_path

puts "Concurrency Validation"
puts "=" * 70
puts "#{THREADS} threads x #{REQUESTS_PER_THREAD} requests = #{THREADS * REQUESTS_PER_THREAD} total"
puts "Target: #{url}"
puts

def run_threaded(name, threads, requests_per_thread)
  results = Array.new(threads) { { success: 0, failure: 0, errors: [] } }
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  workers = threads.times.map do |i|
    Thread.new(i) do |thread_id|
      requests_per_thread.times do
        resp = yield
        if resp[:success] && resp[:body] == EXPECTED_BODY
          results[thread_id][:success] += 1
        else
          results[thread_id][:failure] += 1
          results[thread_id][:errors] << resp[:error]
        end
      end
    end
  end

  workers.each(&:join)
  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  total = threads * requests_per_thread
  successes = results.sum { |r| r[:success] }
  failures = results.sum { |r| r[:failure] }
  errors = results.flat_map { |r| r[:errors] }.compact.tally
  elapsed = t_end - t_start

  puts "#{name}"
  puts "-" * 70
  printf "  Total: %d  Success: %d  Failure: %d  Time: %.2fs  RPS: %.0f\n",
    total, successes, failures, elapsed, total / elapsed
  errors.each { |err, count| puts "  Error (#{count}x): #{err}" } if errors.any?
  puts "  Body integrity: #{failures.zero? ? 'PASS' : 'FAIL'}"
  puts
end

# --- Typhoeus direct ---
run_threaded('Typhoeus (direct, shared connection pool)', THREADS, REQUESTS_PER_THREAD) do
  resp = Typhoeus.get(url, cainfo: ca_path)
  { success: resp.success?, body: resp.body, error: (resp.return_message unless resp.success?) }
end

# --- Faraday + Typhoeus adapter (shared client) ---
faraday_client = Faraday.new(url: url, ssl: { ca_file: ca_path }) do |conn|
  conn.adapter :typhoeus
end
faraday_client.get('/')

run_threaded('Faraday + Typhoeus (shared client)', THREADS, REQUESTS_PER_THREAD) do
  begin
    resp = faraday_client.get('/')
    ok = resp.status == 200
    { success: ok, body: resp.body, error: (ok ? nil : "status=#{resp.status}") }
  rescue => e
    { success: false, body: nil, error: "#{e.class}: #{e.message}" }
  end
end

# --- Typhoeus Hydra (concurrent batches from multiple threads) ---
run_threaded('Typhoeus Hydra (5 concurrent per thread)', THREADS, 1) do
  hydra = Typhoeus::Hydra.new(max_concurrency: 5)
  results = []
  REQUESTS_PER_THREAD.times do
    req = Typhoeus::Request.new(url, cainfo: ca_path)
    req.on_complete { |r| results << r }
    hydra.queue(req)
  end
  hydra.run
  all_ok = results.all? { |r| r.success? && r.body == EXPECTED_BODY }
  { success: all_ok, body: all_ok ? EXPECTED_BODY : results.map(&:body).first,
    error: all_ok ? nil : "#{results.count { |r| !r.success? }} failed in batch" }
end

info.server.shutdown
