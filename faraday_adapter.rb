require 'faraday'
require 'faraday/typhoeus'

url = ENV.fetch('TARGET_URL', 'https://httpbin.org')

conn = Faraday.new(url: url) do |f|
  f.adapter :typhoeus
end

response = conn.get('/get')

puts response.status
puts response.body
