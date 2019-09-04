require 'gruff'
require 'pathname'

client_log_dir = File.expand_path("../logs/clients", __FILE__)
client_log_dir = "/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients"

client_log_dir = Pathname.new(client_log_dir)

g = Gruff::Line.new

log_dir = client_log_dir.join("2019-09-04-17-36-1567636587-254648000")

# puts log_dir
STDOUT.sync=true

log_dir.each_entry do |entry|
  file = log_dir.join(entry)
  next unless file.file?

  g.data entry, file.each_line.map(&:to_f)
end

# lines = File.open("/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients/2019-09-04-17-36-1567636587-254648000/19591").each_line

g.write(log_dir.join('chart.png'))

`open #{log_dir.join('chart.png')}`
