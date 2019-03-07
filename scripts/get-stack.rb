#!/usr/bin/ruby -w

def main
  pids = `pidof swarm`.split(' ')
  puts "found #{pids.length} processes: #{pids}"
  pids.map do |pid|
    puts "=== Thread #{pid} ==="
    puts `gdb -ex "set pagination 0" -ex "thread apply all bt" --batch -p #{pid}`
  end
end

main
