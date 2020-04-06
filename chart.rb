#! /usr/bin/env ruby
require 'gruff'
require 'pathname'

client_log_dir = File.expand_path("../logs/clients", __FILE__)
client_log_dir = "/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients"

client_log_dir = Pathname.new(client_log_dir)

g = Gruff::Line.new

log_entry = client_log_dir.entries.map do |entry|
  client_log_dir.join(entry)
end.select { |dir| dir.directory? && dir != client_log_dir }.sort_by do |dir|
  dir.mtime
end.last

log_dir = client_log_dir.join(log_entry)

# log_dir = client_log_dir.join("2019-09-04-17-36-1567636587-254648000")
log_dir = client_log_dir.join(ARGV[0]) if ARGV[0]

time_scale = ENV.fetch("TIME_SCALE") {
  puts "No time scale set assuming TIME_SCALE=1"
  1
}.to_i

puts "Using log_dir #{log_dir}"

raise "#{log_dir} is not a directory" unless log_dir.directory?

# puts log_dir
STDOUT.sync=true

entry_count = 0
log_files = log_dir.entries.map do |entry|
  log_dir.join(entry)
end.select do |file|
  next if file.basename.to_s == "chart.png"
  next if !file.file?
  next if !file.basename.to_s.end_with?("-chart-data.txt")
  true
end

log_files.each do |entry|
  g.data entry.basename.to_s.gsub("-chart-data.txt", ""), entry.each_line.map(&:to_f)
end

entry_count = log_files.first.each_line.count

g.title = "API Client Rate Limit Throttling Sleep Values\nOver Time for #{log_files.count} PIDs"
g.y_axis_label = "Sleep time in seconds"
g.x_axis_label = "Time duration in hours"

label_hash = { 0 => '0', entry_count - 1 => ((entry_count * time_scale) / 3600.0).to_s }
hours = (entry_count * time_scale) / 3600.0

if hours >= 1
  hour_distance = (entry_count / hours.floor.to_f).floor
  hours.floor.times.each do |hour|
    hour += 1
    label_hash[hour_distance * hour] = hour.to_s
  end
end

g.labels = label_hash

# lines = File.open("/Users/rschneeman/Documents/projects/ratelimit-demo/logs/clients/2019-09-04-17-36-1567636587-254648000/19591").each_line
g.write(log_dir.join('chart.png'))

puts log_dir.join('chart.png')
`open #{log_dir.join('chart.png')}`
