require 'benchmark'
require 'socket'
require 'webrick'
require 'httpclient'
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

adapters = { net_http: :net_http, typhoeus: :typhoeus }

clients = adapters.transform_values do |adapter|
  Faraday.new(url: url) { |conn| conn.adapter adapter }
end

# Warmup — connection pool init, JIT
clients.each_value { |c| c.get('/') }

puts "#{n} sequential requests per adapter, #{concurrency} concurrent for Hydra\n\n"

begin
  Benchmark.bm(25) do |x|
    clients.each do |name, client|
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

    # httpclient for comparison (not a Faraday adapter in 2.x)
    x.report("httpclient (sequential):") do
      hc = HTTPClient.new
      n.times { hc.get(url) }
    end
  end
ensure
  server.shutdown
end
