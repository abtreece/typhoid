#!/usr/bin/env ruby
require 'ffi'

module LibC
  extend FFI::Library
  ffi_lib FFI::Library::LIBC

  attach_function :getpid, [], :int
  attach_function :getuid, [], :uint
  attach_function :getgid, [], :uint
end

puts "libc: #{FFI::Library::LIBC}"
puts "pid:  #{LibC.getpid}"
puts "uid:  #{LibC.getuid}"
puts "gid:  #{LibC.getgid}"
