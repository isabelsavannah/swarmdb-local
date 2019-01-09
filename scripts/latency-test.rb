#!/usr/bin/ruby -w

require 'ruby_linear_regression'

$delays = [0, 25, 50, 75, 100, 150, 200, 300, 500]

$prep = "./scripts/crud -p -n localhost:50000 create-db -u u"
$command = "./scripts/crud -p -n localhost:50000 create -k k -v v -u u"

$results = {}

$delays.each do |delay|
  `tc qdisc add dev lo root netem delay #{delay}ms`
  begin
    `#{$prep}`

    start = Time.now
    `#{$command}`
    finish = Time.now

    diff = finish - start

    $results[delay/1000.0] = diff

    puts "#{delay}ms network latency: #{(diff).round(2)}s operation latency (#{(diff/(delay/1000.0)).round(2)})"
  ensure
    `tc qdisc del dev lo root netem delay #{delay}ms`
  end
end

def regression x, y, degree
  x_data = x.map {|xi| (0..degree).map{|pow| (xi**pow) }}
  mx = Matrix[*x_data]
  my = Matrix.column_vector y

  ((mx.t * mx).inv * mx.t * my).transpose.to_a[0].reverse
end

xs = []
ys = []

$results.each do |x, y|
  xs.append x
  ys.append y
end

reg = regression(xs, ys, 1)
puts "#{reg[1].round(3)} base latency"
puts "#{reg[0].round(2)} hops"
