#!/usr/bin/env ruby

require 'logger'
require 'typhoeus'

log = Logger.new(STDOUT)

Typhoeus::Config.verbose = false

log.debug("Curl version: " + Ethon::Curl.version)

request = Typhoeus::Request.new("https://www.google.com")

request.on_complete do |response|
  if response.success?
    # hell yeah
    log.info("HTTP request succeeded: " + response.code.to_s)
  elsif response.timed_out?
    # aw hell no
    log.info("HTTP request timed out")
  elsif response.code == 0
    # Could not get an http response, something's wrong.
    log.debug(response.return_message)
  else
    # Received a non-successful http response.
    log.debug("HTTP request failed: " + response.code.to_s)
  end
end

request.run