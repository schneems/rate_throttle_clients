this_dir = File.expand_path("..", __FILE__)

server_file = File.join(this_dir, "server/config.ru")
client_file = File.join(this_dir, "client/script.rb")


begin
  pid = Process.spawn("puma #{server_file}")

  sleep 4

  system("ruby #{client_file}")
ensure

  if pid
    Process.kill("TERM", pid)
    Process.wait(pid)
  end
end

