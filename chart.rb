require 'gruff'
require 'pathname'

client_log_dir = File.expand_path("../logs/clients", __FILE__)
client_log_dir = "/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients"

client_log_dir = Pathname.new(client_log_dir)

g = Gruff::Line.new

log_entry = client_log_dir.entries.sort_by do |entry|
  client_log_dir.join(entry).mtime
end.last

log_dir = client_log_dir.join(log_entry)

# log_dir = client_log_dir.join("2019-09-04-17-36-1567636587-254648000")
log_dir = client_log_dir.join(ARGV[0]) if ARGV[0]

raise "#{log_dir} is not a directory" unless log_dir.directory?

# puts log_dir
STDOUT.sync=true

log_dir.each_entry do |entry|
  file = log_dir.join(entry)
  next unless file.file?
  next if entry.to_s == "chart.png"

  g.data entry, file.each_line.map(&:to_f)
end

# lines = File.open("/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients/2019-09-04-17-36-1567636587-254648000/19591").each_line
g.write(log_dir.join('chart.png'))

puts log_dir.join('chart.png')
`open #{log_dir.join('chart.png')}`
