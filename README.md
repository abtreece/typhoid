# Typhoid

Exploration and benchmarking of Ruby HTTP client libraries — comparing [Typhoeus](https://github.com/typhoeus/typhoeus) (libcurl via FFI), [HTTP.rb](https://github.com/httprb/http), [httpx](https://gitlab.com/os85/httpx), [Excon](https://github.com/excon/excon), [httpclient](https://github.com/nahi/httpclient), and [Faraday](https://github.com/lostisland/faraday) adapters.

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

Compares sequential and concurrent request throughput across Ruby HTTP clients. Runs against a local WEBrick server to isolate client overhead from network latency.

```
$ bundle exec ruby benchmark.rb
100 sequential requests, 20 concurrent for Hydra/httpx

                                user     system      total        real
net_http (sequential):      0.030987   0.027114   0.058101 (  0.060819)
typhoeus (sequential):      0.027921   0.006180   0.034101 (  0.032995)
typhoeus hydra (20x):       0.018413   0.008402   0.026815 (  0.025023)
httpclient (sequential):    0.017611   0.009057   0.026668 (  0.024709)
http.rb (sequential):       0.025343   0.022475   0.047818 (  0.050925)
excon (sequential):         0.015554   0.007385   0.022939 (  0.021729)
httpx (sequential):         0.035922   0.013852   0.049774 (  0.049687)
httpx (20x):                0.017343   0.006821   0.024164 (  0.022185)
```

## References

- [Improving External API Performance in Rails](https://medium.com/@ryanflach/improving-external-api-performance-in-rails-9fe8ad197044)
- [Ruby Users Be Wary of Net::HTTP](https://engineering.wework.com/ruby-users-be-wary-of-net-http-f284747288b2)
