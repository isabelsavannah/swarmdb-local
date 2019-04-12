#!/usr/bin/ruby -w

if ARGV.length == 2
  $base = ARGV[0].to_i
  $end = ARGV[1].to_i
else
  $base = 50000
  $end = 50004
end

while $base <= $end
  pid = `lsof -t -i:#{$base}`
  if pid.length > 0
    pid.split("\n").map do |apid|
      puts apid
      `kill -9 #{apid}`
    end
  end
  $base += 1
end
