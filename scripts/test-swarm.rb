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

$interval = 1
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
    result, err = execute_operation(command)

    if(err || !op.validate(result))
      $stats_lock.synchronize {
        $stats['errs'] ||= 0
        $stats['errs'] += 1
      }
    else
      op.apply
    end

    $stats_lock.synchronize {
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

def statistics(report_interval = 10)
  while true
    $stats_lock.synchronize {
      puts "#{($stats['ops'] || 0)} operations, #{$stats['errs'] || 0} errors"
      puts "#{$state.size} uuids, #{$state.values.map{|x| x.size}.reduce(:+)} keys"
      $stats = {}
    }
    sleep(report_interval)
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
    !response.include?("err") && response.include?($state[@uuid][@key])
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
    !response.include? "error"
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
    !response.include? "error"
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
    !response.include? "error"
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
    !response.include? "error"
  end
end

main