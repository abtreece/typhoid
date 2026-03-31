require 'typhoeus'
require 'net/http'
require 'webrick'
require 'json'
require_relative 'lib/tls_server'

# Test HTTP edge cases that Core depends on:
# 1. DELETE with body
# 2. Case-sensitive headers
# 3. mTLS with client certificates

results = []

def report(name, pass, detail = nil)
  status = pass ? 'PASS' : 'FAIL'
  msg = "  [#{status}] #{name}"
  msg += " — #{detail}" if detail
  puts msg
  { name: name, pass: pass, detail: detail }
end

# =====================================================================
# 1. DELETE with body
# =====================================================================
puts "Edge Case Validation"
puts "=" * 70
puts
puts "1. DELETE with body"
puts "-" * 70

# Custom servlet that accepts all HTTP methods and echoes request details
class EchoServlet < WEBrick::HTTPServlet::AbstractServlet
  def service(req, res)
    res['Content-Type'] = 'application/json'
    res.body = JSON.generate({
      method: req.request_method,
      body: req.body,
      headers: req.header
    })
  end
end

server = WEBrick::HTTPServer.new(
  Port: 0,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)
server.mount '/', EchoServlet
Thread.new { server.start }
port = server.listeners.first.addr[1]
10.times do
  TCPSocket.new('localhost', port).close
  break
rescue Errno::ECONNREFUSED
  sleep 0.01
end
http_url = "http://localhost:#{port}/"

# Net::HTTP DELETE with body
uri = URI(http_url)
http = Net::HTTP.new(uri.host, uri.port)
req = Net::HTTP::Delete.new('/')
req.body = '{"id":123}'
req['Content-Type'] = 'application/json'
resp = http.request(req)
parsed = JSON.parse(resp.body)
net_has_body = parsed['body'] == '{"id":123}'
results << report('Net::HTTP DELETE with body', net_has_body,
  net_has_body ? "body received: #{parsed['body']}" : "body lost: #{parsed['body'].inspect}")

# Typhoeus DELETE with body
resp = Typhoeus.delete(http_url, body: '{"id":123}', headers: { 'Content-Type' => 'application/json' })
parsed = JSON.parse(resp.body)
ty_has_body = parsed['body'] == '{"id":123}'
results << report('Typhoeus DELETE with body', ty_has_body,
  ty_has_body ? "body received: #{parsed['body']}" : "body lost: #{parsed['body'].inspect}")

server.shutdown
puts

# =====================================================================
# 2. Case-sensitive headers
# =====================================================================
puts "2. Header case sensitivity"
puts "-" * 70

# Server that echoes headers back with original casing
server2 = WEBrick::HTTPServer.new(
  Port: 0,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)
server2.mount_proc '/' do |req, res|
  res['Content-Type'] = 'application/json'
  # WEBrick downcases header names internally, so we capture the raw request
  # to see what was actually sent. For this test, we'll check what the
  # server receives vs what the client thinks it sent.
  res.body = JSON.generate({ headers: req.header })
end
Thread.new { server2.start }
port2 = server2.listeners.first.addr[1]
10.times do
  TCPSocket.new('localhost', port2).close
  break
rescue Errno::ECONNREFUSED
  sleep 0.01
end
http_url2 = "http://localhost:#{port2}/"

# Net::HTTP: capitalizes header names (Title-Case)
uri2 = URI(http_url2)
http2 = Net::HTTP.new(uri2.host, uri2.port)
req2 = Net::HTTP::Get.new('/')
req2['x-custom-HEADER'] = 'test-value'
req2['X-Mixed-Case'] = 'another-value'
resp2 = http2.request(req2)
net_headers = JSON.parse(resp2.body)['headers']
# Net::HTTP converts to lowercase for the accessor but sends Title-Case on wire
# WEBrick receives and lowercases — so we check that our value arrived
net_custom = net_headers['x-custom-header']&.first
results << report('Net::HTTP sends custom header',
  net_custom == 'test-value',
  "x-custom-header received as: #{net_custom.inspect}")

# Typhoeus: sends headers as-is (whatever case you provide)
resp3 = Typhoeus.get(http_url2, headers: {
  'x-custom-HEADER' => 'test-value',
  'X-Mixed-Case' => 'another-value'
})
ty_headers = JSON.parse(resp3.body)['headers']
ty_custom = ty_headers['x-custom-header']&.first
results << report('Typhoeus sends custom header',
  ty_custom == 'test-value',
  "x-custom-header received as: #{ty_custom.inspect}")

puts
puts "  Note: Both clients deliver the header value correctly."
puts "  Net::HTTP normalizes to Title-Case on the wire (X-Custom-Header)."
puts "  Typhoeus/libcurl sends exactly what you provide (x-custom-HEADER)."
puts "  WEBrick normalizes to lowercase on receipt, so both appear identical here."
puts "  For servers that check header name case, Typhoeus preserves the original."

server2.shutdown
puts

# =====================================================================
# 3. mTLS with client certificates
# =====================================================================
puts "3. mTLS with client certificates"
puts "-" * 70

info = TLSServer.start(require_client_cert: true)

# Net::HTTP with client cert
uri_mtls = URI(info.url)
http_mtls = Net::HTTP.new(uri_mtls.host, uri_mtls.port)
http_mtls.use_ssl = true
http_mtls.ca_file = info.ca_path
http_mtls.cert = OpenSSL::X509::Certificate.new(File.read(info.client_cert_path))
http_mtls.key = OpenSSL::PKey::RSA.new(File.read(info.client_key_path))
begin
  resp_mtls = http_mtls.request(Net::HTTP::Get.new('/'))
  results << report('Net::HTTP mTLS', resp_mtls.code == '200', "status=#{resp_mtls.code}")
rescue => e
  results << report('Net::HTTP mTLS', false, "#{e.class}: #{e.message}")
end

# Typhoeus with client cert
resp_ty = Typhoeus.get(info.url,
  cainfo: info.ca_path,
  sslcert: info.client_cert_path,
  sslkey: info.client_key_path)
results << report('Typhoeus mTLS', resp_ty.success?, resp_ty.success? ? "status=#{resp_ty.code}" : resp_ty.return_message)

# Without client cert — should fail
resp_no = Typhoeus.get(info.url, cainfo: info.ca_path)
results << report('mTLS rejects missing cert', !resp_no.success?,
  resp_no.success? ? 'connected without cert (BAD)' : "rejected: #{resp_no.return_code}")

info.server.shutdown
puts

# =====================================================================
# Summary
# =====================================================================
puts "=" * 70
passed = results.count { |r| r[:pass] }
total = results.length
puts "#{passed}/#{total} tests passed"
exit(1) if passed < total
