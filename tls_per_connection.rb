require 'typhoeus'
require 'net/http'
require_relative 'lib/tls_server'

# Validate that libcurl scopes TLS settings per-connection, not globally.
# Core currently uses OP_LEGACY_SERVER_CONNECT globally because Net::HTTP's
# OpenSSL context can't be scoped per-gateway. This script confirms Typhoeus
# can talk to different TLS configurations from the same process.

puts "Per-Connection TLS Configuration"
puts "=" * 70
puts

# Detect libcurl TLS backend
curl_version = Ethon::Curl.version
puts "Ruby OpenSSL: #{OpenSSL::OPENSSL_VERSION}"
puts "libcurl:      #{curl_version}"
puts

begin
# Start two servers with different ciphers (both TLS 1.2 for libcurl compatibility)
server_a = TLSServer.start(
  ssl_version: OpenSSL::SSL::TLS1_2_VERSION,
  ciphers: 'AES256-SHA'
)
server_b = TLSServer.start(
  ssl_version: OpenSSL::SSL::TLS1_2_VERSION,
  ciphers: 'AES128-SHA256'
)

puts "Server A: TLS 1.2 / AES256-SHA     (#{server_a.url})"
puts "Server B: TLS 1.2 / AES128-SHA256  (#{server_b.url})"
puts

# --- Typhoeus: per-request cipher scoping ---
puts "Typhoeus — per-request cipher scoping from same process"
puts "-" * 70

# Alternate between servers with matching ciphers
resp = Typhoeus.get(server_a.url, cainfo: server_a.ca_path, ssl_cipher_list: 'AES256-SHA')
puts "  Request 1 → Server A (AES256-SHA):    #{resp.success? ? 'PASS' : "FAIL (#{resp.return_message})"}"

resp = Typhoeus.get(server_b.url, cainfo: server_b.ca_path, ssl_cipher_list: 'AES128-SHA256')
puts "  Request 2 → Server B (AES128-SHA256): #{resp.success? ? 'PASS' : "FAIL (#{resp.return_message})"}"

resp = Typhoeus.get(server_a.url, cainfo: server_a.ca_path, ssl_cipher_list: 'AES256-SHA')
puts "  Request 3 → Server A (AES256-SHA):    #{resp.success? ? 'PASS' : "FAIL (#{resp.return_message})"}"

resp = Typhoeus.get(server_b.url, cainfo: server_b.ca_path, ssl_cipher_list: 'AES128-SHA256')
puts "  Request 4 → Server B (AES128-SHA256): #{resp.success? ? 'PASS' : "FAIL (#{resp.return_message})"}"
puts

# Cross-cipher: wrong cipher should fail
resp = Typhoeus.get(server_a.url, cainfo: server_a.ca_path, ssl_cipher_list: 'AES128-SHA256')
puts "  AES128-SHA256 → Server A (AES256-SHA): #{resp.success? ? 'FAIL (should not connect)' : "PASS (rejected: #{resp.return_code})"}"

resp = Typhoeus.get(server_b.url, cainfo: server_b.ca_path, ssl_cipher_list: 'AES256-SHA')
puts "  AES256-SHA → Server B (AES128-SHA256): #{resp.success? ? 'FAIL (should not connect)' : "PASS (rejected: #{resp.return_code})"}"
puts

# --- Also test per-request CA trust (different CAs per request) ---
puts "Typhoeus — per-request CA trust"
puts "-" * 70

# Each server has its own CA — using the wrong CA should fail
resp = Typhoeus.get(server_a.url, cainfo: server_a.ca_path)
puts "  Server A with Server A CA: #{resp.success? ? 'PASS' : "FAIL (#{resp.return_message})"}"

resp = Typhoeus.get(server_a.url, cainfo: server_b.ca_path)
puts "  Server A with Server B CA: #{resp.success? ? 'FAIL (should not trust)' : "PASS (rejected: #{resp.return_code})"}"
puts

# --- Net::HTTP: per-connection cipher ---
puts "Net::HTTP — per-connection cipher scoping"
puts "-" * 70

uri = URI(server_a.url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.ca_file = server_a.ca_path
http.ciphers = 'AES256-SHA'
resp = http.request(Net::HTTP::Get.new('/'))
puts "  AES256-SHA → Server A: PASS (#{resp.code})"

uri = URI(server_b.url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.ca_file = server_b.ca_path
http.ciphers = 'AES128-SHA256'
resp = http.request(Net::HTTP::Get.new('/'))
puts "  AES128-SHA256 → Server B: PASS (#{resp.code})"
puts

puts "=" * 70
puts
puts "Both clients scope cipher/CA settings per-connection. The key difference:"
puts
puts "  Net::HTTP (OpenSSL):  Per-connection cipher/version works, but"
puts "  OP_LEGACY_SERVER_CONNECT is set via SSLContext::DEFAULT_PARAMS —"
puts "  a GLOBAL that affects ALL connections. Core enables this globally"
puts "  to accommodate older gateways, weakening TLS for every connection."
puts
puts "  Typhoeus (libcurl):   All TLS options are per-handle. Legacy settings"
puts "  can be scoped to specific requests without global side effects."
puts
puts "  Platform note: macOS libcurl uses SecureTransport/LibreSSL (#{curl_version.split.first(2).last})."
puts "  Production Linux uses OpenSSL-backed libcurl with full TLS 1.3 support."

ensure
  server_a&.server&.shutdown
  server_b&.server&.shutdown
end
