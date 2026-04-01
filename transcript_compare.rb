require 'typhoeus'
require 'net/http'
require 'stringio'
require_relative 'lib/tls_server'

# Compare debug/verbose output between Net::HTTP and Typhoeus.
# CoreGatekeeperConnection parses Net::HTTP's set_debug_output format
# to detect gzipped responses. This script shows what switching to
# libcurl verbose mode would change for transcript handling.

info = TLSServer.start
url = info.url
uri = URI(url)

begin
  puts "Transcript Format Comparison"
  puts "=" * 70
  puts "Target: #{url}"
  puts

  # --- Net::HTTP: set_debug_output ---
  puts "Net::HTTP — set_debug_output transcript"
  puts "-" * 70

  transcript = StringIO.new
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.ca_file = info.ca_path
  http.set_debug_output(transcript)
  http.request(Net::HTTP::Get.new('/'))

  puts transcript.string
  puts

  puts "Format notes:"
  puts "  - Lines prefixed with '<-' are sent data (request)"
  puts "  - Lines prefixed with '->' are received data (response)"
  puts "  - SSL state/cert details interspersed"
  puts "  - CoreGatekeeperConnection regex-parses this format"
  puts "  - Gzip detection relies on Content-Encoding header in this output"
  puts

  # --- Typhoeus: CURLOPT_VERBOSE ---
  puts "Typhoeus — libcurl verbose mode transcript"
  puts "-" * 70

  # libcurl writes verbose output to stderr via native fd 2, not Ruby's $stderr.
  # Capture at the file descriptor level to catch native output.
  reader, writer = IO.pipe
  old_stderr = STDERR.dup
  STDERR.reopen(writer)

  Typhoeus.get(url, cainfo: info.ca_path, verbose: true, forbid_reuse: true)

  STDERR.reopen(old_stderr)
  old_stderr.close
  writer.close
  verbose_output = reader.read
  reader.close

  puts verbose_output
  puts

  puts "Format notes:"
  puts "  - '(OUT)' / '(IN)' labels for TLS handshake data"
  puts "  - Request headers appear without prefix (bare 'GET / HTTP/1.1')"
  puts "  - Response headers appear without prefix (bare 'HTTP/1.1 200 OK')"
  puts "  - Connection info, DNS, cert chain printed as plain lines"
  puts "  - TLS version, cipher, cert subject/issuer/dates all included"
  puts "  - Very different format from Net::HTTP — parsers must be rewritten"
  puts

  # --- Side-by-side format comparison ---
  puts "Key format differences for transcript migration"
  puts "-" * 70
  puts
  puts "  Net::HTTP:  'opening connection to localhost:#{uri.port}...'"
  puts "  libcurl:    '* Connected to localhost (::1) port #{uri.port}'"
  puts
  puts "  Net::HTTP:  '<- \"GET / HTTP/1.1\\r\\n\"'  (quoted, escaped, '<-' prefix)"
  puts "  libcurl:    'GET / HTTP/1.1'             (bare, no prefix)"
  puts
  puts "  Net::HTTP:  '-> \"HTTP/1.1 200 OK\\r\\n\"'  (quoted, escaped, '->' prefix)"
  puts "  libcurl:    'HTTP/1.1 200 OK'             (bare, no prefix)"
  puts
  puts "  Net::HTTP:  SSL info is minimal ('SSL established, protocol: TLSv1.3')"
  puts "  libcurl:    Full cert chain, subject, issuer, dates, SAN verification"
  puts
  puts "  CoreGatekeeperConnection impact:"
  puts "    Transcript parser searches '->' prefixed lines for Content-Encoding."
  puts "    libcurl output has no line prefixes and no quoting — the parser"
  puts "    would need to be rewritten, but the new format is arguably simpler."
ensure
  info.server.shutdown
end
