#!/usr/bin/ruby -w

require 'thread'
require 'open3'

$state = {}

$stats = {}
$stats_lock = Mutex.new

$uuids_per_worker = 100
$create_db_chance = 0.01

$keys_cap = 1000
$create_chance = 0.1
$delete_chance = 0.05
$read_chance = 0.85

$interval = 0.5
$timeout = 10

$base_port = 50000
$nodes = 4

def rand_string(length)
  (0..length).map { (65 + rand(26)).chr }.join
end

def pick_operation(id)
  uuid_prefix = id.to_s + "/"
  my_uuids = $state.keys.select{|x| x.start_with? uuid_prefix}

  if(my_uuids.size == 0 || (my_uuids.size < $uuids_per_worker && rand < $create_db_chance))
    return Create_db.new(uuid_prefix + rand_string(8))
  end

  uuid = my_uuids.sample

  if($state[uuid].size == 0 || ($state[uuid].size < $keys_cap && rand < $create_chance))
    return Create.new(uuid, rand_string(8), rand_string(32))
  end

  if(rand < $delete_chance)
    return Delete.new(uuid, $state[uuid].keys.sample)
  end

  if(rand < $read_chance)
    return Read.new(uuid, $state[uuid].keys.sample)
  end

  return Update.new(uuid, $state[uuid].keys.sample, rand_string(32))
end

def prefix
  "./scripts/crud -n localhost:#{$base_port + rand($nodes)} -p "
end

def work(i)
  puts "Starting worker thread " + i.to_s
  while true
    op = pick_operation(i)
    command = prefix + op.to_s
    time_before = Time.now.to_f
    result, err = execute_operation(command)
    latency = Time.now.to_f - time_before

    err ||= op.validate(result)

    $stats_lock.synchronize {
      if err
        $stats['errs'] ||= 0
        $stats['errs'] += 1
        $stats['err_counts'] ||= {}
        $stats['err_counts'][err] ||= 0
        $stats['err_counts'][err] += 1
      else
        op.apply
        $stats['latency'] ||= []
        $stats['latency'].push latency
      end
      $stats['ops'] ||= 0
      $stats['ops'] += 1
    }

    sleep((1+rand)*$interval)
  end
end

def execute_operation(command)
  Open3.popen2e(command) do |stdin, stdout, thread|
    if(thread.join($timeout) == nil)
      thread.terminate
      return "", "timeout"
    else
      return stdout.read, nil
    end
  end
end

def statistics(report_interval = 30)
  last_time = Time.now.to_f
  while true
    sleep(report_interval)
    $stats_lock.synchronize {
      interval = Time.now.to_f - last_time

      puts 
      puts "-"*40

      puts "Ran for #{interval.to_f.round(2)} seconds"
      
      puts
      ops = $stats['ops'] || 0
      errs = $stats['errs'] || 0
      err_rate = ops > 0 ? (100*errs/ops).round(0) : "--"
      puts "Tried to execute #{ops} operations (#{(ops/interval).round(1)}/sec), #{errs} (#{err_rate}%) yielded an error"
      if errs > 0
        puts "  error breakdown:"
        $stats['err_counts'].map do |name, amount|
          puts "  #{amount} #{name}"
        end
      end

      if $stats['latency'] && $stats['latency'].size > 0
        puts
        puts "Latency statistics for sucessful operations, in ms:"
        data = $stats['latency'].sort
        puts "  min:    " + (data[0]*1000).to_i.to_s
        puts "  mean:   " + (data.reduce(0, :+)/data.length*1000).to_i.to_s
        puts "  median: " + (median(data)*1000).to_i.to_s
        puts "  p90:    " + (percentile(data, 0.9)*1000).to_i.to_s
        puts "  p99:    " + (percentile(data, 0.99)*1000).to_i.to_s
        puts "  max:    " + (data[-1]*1000).to_i.to_s
      end


      puts
      puts "The database contains #{$state.size} uuids, with a total of #{$state.values.map{|x| x.size}.reduce(0, :+)} keys"

      puts "-"*40
      puts

      $stats = {}
      last_time = Time.now.to_f
    }
  end
end

def percentile(arr, p)
  if arr.length == 1
    return arr[0]
  end

  target = (arr.length - 1)*p

  base = target.to_i
  weight = target - target.to_i
  
  return arr[base] * (1-weight) + arr[base+1] * weight
end



def median(arr)
  if arr.length % 2 == 0
    (arr[arr.length/2] + arr[arr.length/2 - 1])/2
  else
    arr[arr.length/2]
  end
end

def main
  threads = []
  threads.push Thread.new {statistics}
  threads.push Thread.new {work 1}

  threads.map{|x| x.join}
end

class Read
  def initialize(uuid, key)
    @uuid = uuid
    @key = key
  end

  def apply

  end

  def to_s
    "read -u #{@uuid} -k #{@key}"
  end

  def validate(response)
    if(response.include?("err"))
     return "inferred-err"
    end

    if !response.include?($state[@uuid][@key])
      return "wrong-value"
    end

    return nil
  end
end

class Create
  def initialize(uuid, key, value)
    @uuid = uuid
    @key = key
    @value = value
  end

  def apply
    $state[@uuid][@key] = @value
  end

  def to_s
    "create -u #{@uuid} -k #{@key} -v #{@value}"
  end
  
  def validate(response)
    if(response.include?("err"))
     return "inferred-err"
    end

    return nil
  end
end

class Update
  def initialize(uuid, key, value)
    @uuid = uuid
    @key = key
    @value = value
  end

  def apply
    $state[@uuid][@key] = @value
  end

  def to_s
    "update -u #{@uuid} -k #{@key} -v #{@value}"
  end
  
  def validate(response)
    if(response.include?("err"))
     return "inferred-err"
    end

    return nil
  end
end

class Delete
  def initialize(uuid, key)
    @uuid = uuid
    @key = key
  end

  def apply
    $state[@uuid].delete(@key)
  end

  def to_s
    "delete -u #{@uuid} -k #{@key}"
  end

  def validate(response)
    if(response.include?("err"))
     return "inferred-err"
    end

    return nil
  end
end

class Create_db
  def initialize(uuid)
    @uuid = uuid
  end

  def apply
    $state[@uuid] = {}
  end

  def to_s
    "create-db -u #{@uuid}"
  end

  def validate(response)
    if(response.include?("err"))
     return "inferred-err"
    end

    return nil
  end
end

main
