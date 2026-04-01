require 'net/http'
require 'faraday'
require 'faraday/typhoeus'
require 'typhoeus'
require_relative 'lib/tls_server'

# Compare TLS error diagnostics between Net::HTTP and Typhoeus/libcurl.
# Forces 4 common TLS failure modes and captures error output from each client.

# libcurl CURLOPT_SSLVERSION constants (not exposed by ethon)
CURL_SSLVERSION_TLSv1_2     = 6
CURL_SSLVERSION_MAX_TLSv1_2 = 0x20000

def test_net_http(url, ca_path)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.ca_file = ca_path
  http.open_timeout = 5
  http.read_timeout = 5
  http.request(Net::HTTP::Get.new('/'))
  'OK (unexpected success)'
rescue => e
  "#{e.class}: #{e.message}"
end

def test_typhoeus(url, ca_path, **opts)
  resp = Typhoeus.get(url, { cainfo: ca_path, timeout: 5, connecttimeout: 5 }.merge(opts))
  if resp.success?
    'OK (unexpected success)'
  else
    "code=#{resp.response_code} curl_code=#{resp.return_code} msg=#{resp.return_message}"
  end
end

def test_faraday_typhoeus(url, ca_path)
  conn = Faraday.new(url: url, ssl: { ca_file: ca_path }) do |f|
    f.adapter :typhoeus
  end
  conn.get('/')
  'OK (unexpected success)'
rescue => e
  "#{e.class}: #{e.message}"
end

servers = []

begin
puts "TLS Error Diagnostics Comparison"
puts "=" * 90
puts

# 1. Expired certificate
puts "1. Expired certificate"
puts "-" * 90
info = TLSServer.start(leaf_not_before: Time.now - 7200, leaf_not_after: Time.now - 3600)
servers << info
puts "  Net::HTTP:  #{test_net_http(info.url, info.ca_path)}"
puts "  Typhoeus:   #{test_typhoeus(info.url, info.ca_path)}"
puts "  Faraday+Ty: #{test_faraday_typhoeus(info.url, info.ca_path)}"
puts

# 2. Wrong hostname
puts "2. Wrong hostname (cert CN=wrong.example.com, connecting to localhost)"
puts "-" * 90
info = TLSServer.start(leaf_cn: 'wrong.example.com', leaf_sans: ['wrong.example.com'])
servers << info
puts "  Net::HTTP:  #{test_net_http(info.url, info.ca_path)}"
puts "  Typhoeus:   #{test_typhoeus(info.url, info.ca_path)}"
puts "  Faraday+Ty: #{test_faraday_typhoeus(info.url, info.ca_path)}"
puts

# 3. Protocol rejection (server TLS 1.3 only, client forces TLS 1.2)
puts "3. Protocol mismatch (server=TLS1.3 only, client=TLS1.2 only)"
puts "-" * 90
info = TLSServer.start(ssl_version: OpenSSL::SSL::TLS1_3_VERSION)
servers << info
uri = URI(info.url)
# Net::HTTP: max_version pins to TLS 1.2
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.ca_file = info.ca_path
http.max_version = OpenSSL::SSL::TLS1_2_VERSION
http.open_timeout = 5
begin
  http.request(Net::HTTP::Get.new('/'))
  net_result = 'OK (unexpected success)'
rescue => e
  net_result = "#{e.class}: #{e.message}"
end
puts "  Net::HTTP:  #{net_result}"
# Typhoeus: sslversion sets min only; must OR with MAX flag to pin
puts "  Typhoeus:   #{test_typhoeus(info.url, info.ca_path, sslversion: CURL_SSLVERSION_TLSv1_2 | CURL_SSLVERSION_MAX_TLSv1_2)}"
puts "  NOTE:       Typhoeus sslversion: :tlsv1_2 only sets MINIMUM version."
puts "              Must use numeric CURL_SSLVERSION_TLSv1_2 | CURL_SSLVERSION_MAX_TLSv1_2 to pin."
puts

# 4. Cipher mismatch (TLS 1.2 server with AES256-SHA, client requests AES128-SHA)
puts "4. Cipher mismatch (server=AES256-SHA, client=AES128-SHA)"
puts "-" * 90
info = TLSServer.start(ssl_version: OpenSSL::SSL::TLS1_2_VERSION, ciphers: 'AES256-SHA')
servers << info
uri = URI(info.url)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.ca_file = info.ca_path
http.ciphers = 'AES128-SHA'
http.open_timeout = 5
begin
  http.request(Net::HTTP::Get.new('/'))
  net_result = 'OK (unexpected success)'
rescue => e
  net_result = "#{e.class}: #{e.message}"
end
puts "  Net::HTTP:  #{net_result}"
puts "  Typhoeus:   #{test_typhoeus(info.url, info.ca_path, ssl_cipher_list: 'AES128-SHA')}"
puts

puts "=" * 90
puts
puts "Analysis:"
puts
puts "  Net::HTTP (OpenSSL):  All failures → OpenSSL::SSL::SSLError with varying messages."
puts "  The message text distinguishes failure modes but requires string parsing."
puts "  In Core, gatekeeper catches this as a single exception type."
puts
puts "  Typhoeus (libcurl):   Failures → distinct return_code symbols:"
puts "    - peer_failed_verification: cert expired, hostname mismatch, untrusted CA"
puts "    - ssl_connect_error:        protocol/cipher negotiation failures"
puts "  Programmatic classification via return_code, no regex needed."
puts
puts "  Faraday+Typhoeus:     Wraps libcurl errors as Faraday::ConnectionFailed."
puts "  Original libcurl message preserved. Can inspect response for return_code."

ensure
  servers.each { |s| s.server.shutdown }
end
