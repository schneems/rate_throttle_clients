this_dir = File.expand_path("..", __FILE__)
server_dir = File.join(this_dir, "server")
client_file = File.join(this_dir, "client/script.rb")

fork do
  out = `cd #{server_dir} && puma`
  puts out
end

sleep 4

exec("ruby #{client_file}")

