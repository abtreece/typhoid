require 'faraday'
require 'faraday/typhoeus'

conn = Faraday.new(url: 'https://httpbin.org') do |f|
  f.adapter :typhoeus
end

response = conn.get('/get')

puts response.status
puts response.body
