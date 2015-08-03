# encoding: utf-8

module DHTDigger
  module Diggers
  end
end

require 'logger'
require_relative 'diggers/wiretap'

logger = Logger.new(STDOUT)
#logger.level = Logger::DEBUG
logger.level = Logger::INFO

GOOD_NODES = [
  {'ip' => 'router.bittorrent.com', 'port' => '6881'},
  {'ip' => 'dht.transmissionbt.com', 'port' => '6881'},
  {'ip' => 'router.utorrent.com', 'port' => '6881'},
]

datadig = DHTDigger::Digger::Wiretap.new('0.0.0.0', '6881',  GOOD_NODES, logger)
datadig.setup
datadig.run