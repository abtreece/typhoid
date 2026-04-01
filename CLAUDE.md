# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Typhoid is a collection of standalone Ruby scripts for exploring and benchmarking Ruby HTTP client libraries — primarily Typhoeus (libcurl via FFI/Ethon), Faraday with various adapters, and httpclient.

## Setup

```
bundle install
```

Requires Ruby 3.4.1 (set in `.ruby-version`, `.tool-versions`, and `Gemfile`).

## Running Scripts

Each `.rb` file is a standalone script. Run with `bundle exec`:

```
bundle exec ruby typhoid.rb       # basic Typhoeus HTTP request
bundle exec ruby benchmark.rb     # benchmark net_http vs typhoeus vs httpclient via Faraday
bundle exec ruby faraday_adapter.rb  # Faraday with Typhoeus adapter
bundle exec ruby ffi.rb           # FFI/libc loading test
```

## Architecture

There is no library or gem structure — these are independent exploration scripts, not a package. No tests exist.

- **typhoid.rb** — direct Typhoeus request with response handling callbacks
- **benchmark.rb** — `Benchmark.bm` comparing HTTP clients (net_http and typhoeus via Faraday; httpclient, http.rb, excon, httpx directly; plus Hydra and httpx concurrent modes)
- **faraday_adapter.rb** — minimal Faraday + Typhoeus adapter example
- **ffi.rb** — FFI library loading proof-of-concept (loads libc)
- **lib/tls_server.rb** — shared helper for TLS validation scripts: runtime CA/leaf cert generation, WEBrick HTTPS server on ephemeral port, mTLS support, configurable TLS versions/ciphers

## Dependencies

Key gems: `typhoeus` (libcurl via `ethon`/`ffi`), `faraday` 2.x + `faraday-typhoeus`, `http` (HTTP.rb), `httpx`, `excon`, `httpclient`, `webrick` (local benchmark server).
