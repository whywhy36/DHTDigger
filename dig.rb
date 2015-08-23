# encoding: utf-8

module DHTDigger
  module Diggers
  end
end

require 'logger'
require 'yaml'
require_relative 'diggers/wiretap'

file_path = '/Users/yuanzhuang/temp/dhtpids/dht_digger.pid'

File.open(file_path, 'a') unless File.exist?(file_path)

all_diggers = []
trap('TERM') do
  puts 'Receiving terminate signal ...'
  all_diggers.each { |pid| Process.kill(:TERM, pid)}
  exit
end

config = YAML.load_file("#{File.dirname(__FILE__)}/configuration/config.yml")

redis_config = config['redis']
wiretap_options = config['wiretap_options']
dht_hosts = config['dht_hosts']
logging_config = config['logging']

wiretap_config = config['wiretap']

wiretap_config.each do |each_config|
  all_diggers << fork do
    name = each_config['name']
    host = each_config['host']
    port = each_config['port']
    private_logger = Logger.new("#{logging_config['output']}#{name}.log")
    private_logger.level = Logger::INFO

    single_digger = DHTDigger::Diggers::Wiretap.new(
        host, port, dht_hosts, redis_config, private_logger, wiretap_options)

    single_digger.setup
    single_digger.run
  end
end

at_exit do
  # check PID file and delete it
  puts 'Deleting PID file'
  File.delete(file_path) if File.exist?(file_path)
  puts 'Exiting ...'
end

puts "Starting #{all_diggers.size} digger(s) ..."
Process.waitall