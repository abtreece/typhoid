require 'typhoeus'
require 'net/http'
require_relative 'lib/tls_server'

# Validate Typhoeus timing metrics (from libcurl curl_easy_getinfo).
# Shows the phase breakdown that Net::HTTP lacks — DNS, TCP, TLS, TTFB, total.

info = TLSServer.start
url = info.url
uri = URI(url)

puts "Connection Timing Phases"
puts "=" * 70
puts "Target: #{url}"
puts

# --- Typhoeus: full phase breakdown ---
puts "Typhoeus (libcurl) — timing phases"
puts "-" * 70

# Fresh connection (no pooling) to see all phases
resp = Typhoeus.get(url, cainfo: info.ca_path, forbid_reuse: true)
phases = {
  'namelookup_time'  => resp.namelookup_time,
  'connect_time'     => resp.connect_time,
  'appconnect_time'  => resp.appconnect_time,
  'pretransfer_time' => resp.pretransfer_time,
  'starttransfer_time' => resp.starttransfer_time,
  'total_time'       => resp.total_time
}

phases.each do |name, value|
  printf "  %-22s %8.3f ms\n", name, value * 1000
end

puts
puts "  Phase breakdown:"
printf "    DNS resolution:      %8.3f ms\n", phases['namelookup_time'] * 1000
printf "    TCP connect:         %8.3f ms\n", (phases['connect_time'] - phases['namelookup_time']) * 1000
printf "    TLS handshake:       %8.3f ms\n", (phases['appconnect_time'] - phases['connect_time']) * 1000
printf "    Request/response:    %8.3f ms\n", (phases['starttransfer_time'] - phases['pretransfer_time']) * 1000
printf "    Total:               %8.3f ms\n", phases['total_time'] * 1000
puts

# Verify monotonic ordering
ordered = phases.values.each_cons(2).all? { |a, b| a <= b }
puts "  Monotonic ordering: #{ordered ? 'PASS' : 'FAIL'}"
puts

# --- Pooled connection: TLS phase should be zero ---
puts "Typhoeus — pooled connection (reused)"
puts "-" * 70

# Warmup to establish pool
Typhoeus.get(url, cainfo: info.ca_path)
resp_pooled = Typhoeus.get(url, cainfo: info.ca_path)

printf "  appconnect_time:     %8.3f ms (TLS handshake — should be ~0 on reuse)\n",
  resp_pooled.appconnect_time * 1000
printf "  starttransfer_time:  %8.3f ms (TTFB)\n",
  resp_pooled.starttransfer_time * 1000
printf "  total_time:          %8.3f ms\n",
  resp_pooled.total_time * 1000
puts

# --- Multiple requests: show timing consistency ---
puts "Typhoeus — 10 sequential requests (pooled)"
puts "-" * 70
printf "  %-4s  %-10s  %-10s  %-10s  %-10s\n", '#', 'DNS', 'TLS', 'TTFB', 'Total'
10.times do |i|
  r = Typhoeus.get(url, cainfo: info.ca_path)
  printf "  %-4d  %8.3f ms  %8.3f ms  %8.3f ms  %8.3f ms\n",
    i + 1,
    r.namelookup_time * 1000,
    r.appconnect_time * 1000,
    r.starttransfer_time * 1000,
    r.total_time * 1000
end
puts

# --- Net::HTTP: what's available ---
puts "Net::HTTP — timing capabilities"
puts "-" * 70
puts "  Net::HTTP provides NO built-in timing breakdown."
puts "  Only wall-clock measurement is available:"
puts

t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.ca_file = info.ca_path
http.request(Net::HTTP::Get.new('/'))
t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)

printf "  Wall-clock total: %.3f ms (no phase breakdown)\n", (t_end - t_start) * 1000
puts
puts "  This is all gatekeeper captures today: gateway_latency_ms."
puts "  There is no way to isolate DNS, TCP, TLS, or TTFB without external tooling."

info.server.shutdown
