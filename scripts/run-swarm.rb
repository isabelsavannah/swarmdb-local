#!/usr/bin/ruby -w

if(ARGV.length > 0)
  $swarm_size = ARGV[0].to_i
else
  $swarm_size = 4
end

`rm -rf local/nodes/`
base_dir = `pwd`.strip
peers_file = base_dir + "/local/nodes/peers.json"

peers = []
execute_commands = []

(0...$swarm_size).each do |i|
  node_name = "node" + i.to_s;
  node_dir = base_dir + "/" + "local/nodes/#{node_name}"

  `mkdir -p #{node_dir}`
  Dir.chdir(node_dir);

  `cp #{base_dir}/build/output/swarm ./`
  `#{base_dir}/scripts/generate-key`

  lines = []
  File.readlines(node_dir + "/.state/public-key.pem").each do |line|
    lines.push(line)
  end

  node_uuid = lines[1..-2].map{|x| x.strip}.join()
  peers.push %({
      "name": "node#{i}", 
      "host": "127.0.0.1", 
      "port": #{50000+i}, 
      "http_port": #{5080+i}, 
      "uuid": "#{node_uuid}"
    })

  File.write(node_dir + "/bluzelle.json", %({
    "listener_address" : "127.0.0.1",
    "listener_port" : #{50000+i},
    "ethereum" : "0xddbd2b932c763ba5b1b7ae3b362eac3e8d40121a",
    "ethereum_io_api_token" : "**********************************",
    "bootstrap_file" : "#{peers_file}",
    "debug_logging" : true,
    "log_to_stdout" : true,
    "use_pbft": true,
    "audit_enabled": true,
    "chaos_testing_enabled": false,
    "monitor_address": "localhost",
    "monitor_port": 8125
    }))

  execute_commands.push %(gnome-terminal -- bash -c "cd #{node_dir}; #{node_dir}/swarm -c #{node_dir}/bluzelle.json; bash")
end

File.write(peers_file, '[' + peers.join(",\n") + ']')

execute_commands.each do |command|
  `#{command}`
end
