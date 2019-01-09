#!/usr/bin/ruby -w

require 'thread'
require 'open3'

$threads = 6
$latency = 100 #ms

def pick_operation
  return "./scripts/crud -p -n localhost:5000#{rand(4)} create-db -u \"someuuid#{rand(10000)}\""
end

def work(i)
  op = pick_operation
  puts "starting worker thread " + i.to_s + ": " + op

  time_before = Time.now.to_f
  `#{op}`
  td = Time.now.to_f - time_before

  puts "worker thread #{i} finished in #{(td*1000).round}ms"
end

def main
  begin
    `tc qdisc add dev lo root netem delay #{$latency}ms`
    (0...$threads).map{|x| Thread.new{work x}}.map{|x| x.join}
  ensure
    `tc qdisc del dev lo root netem delay #{$latency}ms`
  end
end

main
