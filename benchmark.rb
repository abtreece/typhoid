require 'benchmark'
require 'socket'
require 'webrick'
require 'httpclient'
require 'http'
require 'httpx'
require 'excon'
require 'faraday'
require 'faraday/typhoeus'
require 'typhoeus'

n = 100
concurrency = 20

# Local server to isolate client overhead from network latency
server = WEBrick::HTTPServer.new(
  Port: 0,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)
server.mount_proc '/' do |_req, res|
  res['Content-Type'] = 'application/json'
  res.body = '{"status":"ok"}'
end
Thread.new { server.start }

port = server.listeners.first.addr[1]
url = "http://localhost:#{port}/"

# Wait for server to accept connections
10.times do
  TCPSocket.new('localhost', port).close
  break
rescue Errno::ECONNREFUSED
  sleep 0.01
end

# Faraday clients (net_http and typhoeus adapters)
faraday_adapters = { net_http: :net_http, typhoeus: :typhoeus }
faraday_clients = faraday_adapters.transform_values do |adapter|
  Faraday.new(url: url) { |conn| conn.adapter adapter }
end

# Warmup — connection pool init, JIT
faraday_clients.each_value { |c| c.get('/') }
HTTP.get(url)
HTTPX.get(url)
Excon.get(url)

puts "#{n} sequential requests, #{concurrency} concurrent for Hydra/httpx\n\n"

begin
  Benchmark.bm(25) do |x|
    # Faraday adapters
    faraday_clients.each do |name, client|
      x.report("#{name} (sequential):") do
        n.times { client.get('/') }
      end
    end

    # Typhoeus Hydra — parallel requests via libcurl multi interface
    x.report("typhoeus hydra (#{concurrency}x):") do
      hydra = Typhoeus::Hydra.new(max_concurrency: concurrency)
      n.times do
        hydra.queue(Typhoeus::Request.new(url))
      end
      hydra.run
    end

    # Direct clients (not through Faraday)
    x.report("httpclient (sequential):") do
      hc = HTTPClient.new
      n.times { hc.get(url) }
    end

    x.report("http.rb (sequential):") do
      n.times { HTTP.get(url) }
    end

    x.report("excon (sequential):") do
      conn = Excon.new(url, persistent: true)
      n.times { conn.get(path: '/') }
    end

    x.report("httpx (sequential):") do
      n.times { HTTPX.get(url) }
    end

    # httpx concurrent — HTTP/2 multiplexing over shared connections
    x.report("httpx (#{concurrency}x):") do
      urls = Array.new(n) { url }
      urls.each_slice(concurrency) do |batch|
        HTTPX.get(*batch)
      end
    end
  end
ensure
  server.shutdown
end
