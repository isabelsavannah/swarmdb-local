#!/usr/bin/ruby -w

def main
  data = []
  pids = `pidof swarm`.split(' ')
  data.push "found #{pids.length} processes: #{pids}"
  threads = pids.map do |pid|
    Thread.new do 
      data.push "=== Process #{pid} ===" + 
        `gdb -ex "set pagination 0" -ex "thread apply all bt" --batch -p #{pid}`
    end
  end

  begin
    threads.map{|t| t.join}
  rescue Interrupt
    threads.map{|t| t.kill}
    data.push "Interrupted!"
  end

  puts data.join("\n")
end

main
