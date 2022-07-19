#!/usr/bin/env ruby
require 'ffi'

puts "libc => #{FFI::Library::LIBC}"

module Test
  extend FFI::Library
  ffi_lib(FFI::Library::LIBC)
  # ffi_lib('libc.dylib')
  # ffi_lib('/usr/lib/libc.dylib')
  puts "successfully loaded: #{ffi_libraries}"
end