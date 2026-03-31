require 'benchmark'
require 'net/http'
require 'faraday'
require 'faraday/typhoeus'
require 'typhoeus'
require_relative 'lib/tls_server'

n = 100
concurrency = 20

info = TLSServer.start
url = info.url
uri = URI(url)
ca_path = info.ca_path

puts "#{n} sequential requests to #{url} (TLS)"
puts "#{concurrency} concurrent for Hydra"
puts

begin
  Benchmark.bm(35) do |x|
    # --- Net::HTTP: fresh connection per request (gatekeeper's current behavior) ---
    x.report('net_http (no reuse):') do
      n.times do
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.ca_file = ca_path
        http.request(Net::HTTP::Get.new('/'))
        http.finish if http.started?
      end
    end

    # --- Net::HTTP: persistent connection ---
    x.report('net_http (persistent):') do
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ca_file = ca_path
      http.start do |conn|
        n.times { conn.request(Net::HTTP::Get.new('/')) }
      end
    end

    # --- Faraday + Net::HTTP adapter (default) ---
    faraday_net = Faraday.new(url: url, ssl: { ca_file: ca_path }) do |conn|
      conn.adapter :net_http
    end
    faraday_net.get('/')
    x.report('faraday net_http (sequential):') do
      n.times { faraday_net.get('/') }
    end

    # --- Typhoeus: forbid_reuse (simulates Connection: close) ---
    x.report('typhoeus (no reuse):') do
      n.times do
        Typhoeus.get(url, cainfo: ca_path, forbid_reuse: true)
      end
    end

    # --- Typhoeus: default connection pooling ---
    Typhoeus.get(url, cainfo: ca_path)
    x.report('typhoeus (pooled):') do
      n.times { Typhoeus.get(url, cainfo: ca_path) }
    end

    # --- Faraday + Typhoeus adapter ---
    faraday_ty = Faraday.new(url: url, ssl: { ca_file: ca_path }) do |conn|
      conn.adapter :typhoeus
    end
    faraday_ty.get('/')
    x.report('faraday typhoeus (sequential):') do
      n.times { faraday_ty.get('/') }
    end

    # --- Typhoeus Hydra (concurrent, pooled) ---
    x.report("typhoeus hydra (#{concurrency}x):") do
      hydra = Typhoeus::Hydra.new(max_concurrency: concurrency)
      n.times do
        hydra.queue(Typhoeus::Request.new(url, cainfo: ca_path))
      end
      hydra.run
    end
  end
ensure
  info.server.shutdown
end
