require 'benchmark'
require 'json'
require 'patron'
require 'httpclient'
require 'faraday'
require 'typhoeus'
require 'typhoeus/adapters/faraday'

n = 100

adapters = [:net_http, :typhoeus, :patron, :httpclient]

def create_client(adapter)
  host = 'https://core.spreedly.com/'

  Faraday.new(url: host, ssl: { verify: false }) do |conn|
    conn.adapter adapter
  end
end

Benchmark.bm(20) do |x|

  adapters.each do |adapter|
    x.report("#{adapter}:") do
      client = create_client(adapter)

      n.times do |i|
        client.get do |req|
          req.url "/v1/gateways_options.json"
          req.headers['Content-Type'] = 'application/json'
        end
      end
    end
  end

end