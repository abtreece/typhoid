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
- **benchmark.rb** — `Benchmark.bm` comparing HTTP clients (net_http and typhoeus via Faraday, httpclient directly, plus Typhoeus Hydra for concurrency)
- **faraday_adapter.rb** — minimal Faraday + Typhoeus adapter example
- **ffi.rb** — FFI library loading proof-of-concept (loads libc)

## Dependencies

Key gems: `typhoeus` (wraps libcurl via `ethon`/`ffi`), `faraday` 2.x + `faraday-typhoeus` (HTTP client abstraction), `httpclient`, `webrick` (local benchmark server).
