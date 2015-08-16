require 'pry'
require_relative 'db/db_ops'

db_ops = DHTDigger::Database::DBOps.new
db_ops.run do |torrent|
  puts "add new torrent with id #{torrent.inspect}"
  gets
end