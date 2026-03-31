# Typhoid

Exploration and benchmarking of Ruby HTTP client libraries — comparing [Typhoeus](https://github.com/typhoeus/typhoeus) (libcurl via FFI), [Faraday](https://github.com/lostisland/faraday) adapters, and [httpclient](https://github.com/nahi/httpclient).

## Setup

Requires Ruby 3.4.1.

```
bundle install
```

## Scripts

```
bundle exec ruby benchmark.rb        # benchmark HTTP clients against a local server
bundle exec ruby typhoid.rb          # Typhoeus request with response callbacks
bundle exec ruby faraday_adapter.rb  # Faraday 2 + Typhoeus adapter
bundle exec ruby ffi.rb              # FFI function binding (libc getpid/getuid/getgid)
```

### Benchmark

Compares sequential request throughput across net_http, Typhoeus, and httpclient, plus concurrent requests via Typhoeus Hydra (libcurl multi interface). Runs against a local WEBrick server to isolate client overhead from network latency.

```
$ bundle exec ruby benchmark.rb
100 sequential requests per adapter, 20 concurrent for Hydra

                                user     system      total        real
net_http (sequential):      0.037079   0.029942   0.067021 (  0.070897)
typhoeus (sequential):      0.026065   0.007279   0.033344 (  0.032752)
typhoeus hydra (20x):       0.023635   0.009770   0.033405 (  0.031150)
httpclient (sequential):    0.018895   0.009908   0.028803 (  0.026705)
```

## References

- [Improving External API Performance in Rails](https://medium.com/@ryanflach/improving-external-api-performance-in-rails-9fe8ad197044)
- [Ruby Users Be Wary of Net::HTTP](https://engineering.wework.com/ruby-users-be-wary-of-net-http-f284747288b2)
