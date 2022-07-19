require 'faraday'
require 'typhoeus'
require 'typhoeus/adapters/faraday'

conn = Faraday.new(:url => 'https://core.spreedly.com') do |faraday|
  faraday.adapter :typhoeus
end

response = conn.get('/v1/gateways_options.json')

puts response.status
puts response.body
