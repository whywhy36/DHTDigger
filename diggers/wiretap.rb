# encoding: utf-8

require 'socket'
require 'bencode'
require 'logger'
require 'eventmachine'
require 'securerandom'
require 'tmpdir'
require 'fileutils'
require 'pry'
require_relative 'krpc'
require_relative 'torrent_helper'
require_relative 'db_ops'

module DHTDigger::Diggers

  # 'bean' style types
  Peer = Struct.new(:ip, :port)
  Metadata = Struct.new(:info_hash, :peer, :type)

  class MetadataProcessor
    include TorrentHelper

    def initialize(queue, name)
      @queue = queue
      @name = name
      @db_ops = DBOps.new('') #TODO:
    end

    def run
      create_workspace

      loop {
        metadata = @queue.pop
        process(metadata)
      }
    rescue => ex
      @logger.error ex.message
      @logger.error ex.backtrace.join("\n")
    end

    def process(metadata)
      @logger.info "process metadata: #{metadata.inspect}" if @logger

      send("process_data_from_#{metadata.type}".to_sym, metadata.info_hash, metadata.peer)
      # parse metadata and store it in database
    end

    def process_data_from_announce_peer(info_hash, peer)
      @logger.info "Processing announce_peer metadata : #{info_hash}"
      # TODO:
    end

    def process_data_from_get_peers(info_hash, peer)
      @logger.info "Processing get_peers metadata : #{info_hash}"
      # TODO:
    end

    def create_workspace
      # TODO: create one temp workspace for storing downloaded file
      FileUtils::mkdir_p './tmp'
      @workspace = Dir.mktmpdir(@name, './tmp')
      @logger = Logger.new("#{@workspace}/worker.log")
      @logger.level = Logger::INFO
    end
  end

  class KadNode
    attr_accessor :id, :ip, :port

    def initialize(id, ip, port)
      @id = id
      @ip = ip
      @port = port
    end
  end

  class Wiretap
    include KRPC

    attr_accessor :dht_hosts
    attr_accessor :socket
    attr_accessor :logger

    def initialize(host, port, dht_hosts, logger)
      @queue = Queue.new
      @host = host
      @port = port
      @dht_hosts = dht_hosts
      @logger = logger

      # TODO: configurable
      # This is a queue for KadNode
      @nodes = SizedQueue.new(200000)
    end

    def setup
      @logger.info "Setting up wiretap ..."
      @node_id = random_node_id.force_encoding('ASCII-8BIT')

      @socket = UDPSocket.new
      @socket.bind(@host, @port)
      
      @logger.info "node id is #{@node_id}, listenning on UDP socket #{@host}:#{@port}"

      start_workers
      start_tap
      
      @logger.info "Setting up done."
    end

    def run
      @logger.info "starting thread with timer to say hello to DHT network"
      
      EM.run do
        join_DHT_network
        EM.add_periodic_timer(10) do
          join_DHT_network
        end

        EM.add_periodic_timer(0.1) do
          heartbeat
        end

        EM.add_periodic_timer(30) do
          information
        end
      end
    end

    def information
      @logger.info "@nodes' size is #{@nodes.size} and @queue's size is #{@queue.size}"
    end

    def join_DHT_network
      return unless @nodes.empty?
      @logger.info "(re)joining DHT network ..."
      @dht_hosts.each do |dht_host|
        message = find_node(@node_id, random_node_id)
        send_krpc_message(message, dht_host['ip'], dht_host['port'])
      end
    end

    def heartbeat
      return if @nodes.empty?
      
      remote_node = @nodes.pop
      remote_node_id = remote_node.id.force_encoding('ASCII-8BIT')

      # create a fake id
      fake_node_id = create_fake_node_id(@node_id, remote_node_id)
      @logger.debug "fake node id is #{fake_node_id}"
      message = find_node(fake_node_id, random_node_id)
      send_krpc_message(message, remote_node.ip, remote_node.port)
    end

    def create_fake_node_id(local_node_id, remote_node_id)
      prefix = remote_node_id.force_encoding('ASCII-8BIT')[0, 11]
      postfix = local_node_id.force_encoding('ASCII-8BIT')[11, 9]

      (prefix + postfix).force_encoding('ASCII-8BIT')
    end

    def start_workers(count=5)
      @logger.info "starting worker"
      @queue = Queue.new if @queue.nil?
      count.times do |i|
        worker_name = "worker_#{i}_#{SecureRandom.uuid[0, 8]}"
        Thread.new do
          begin
          @logger.info "starting worker #{worker_name}"
          worker = MetadataProcessor.new(@queue, worker_name)
          worker.run
        rescue => ex
          @logger.error ex.message
          @logger.error ex.backtrace.join("\n")
        end
        end
      end
    end

    def stop_workers
      #TODO
    end

    def start_tap
      @logger.info "starting tap"
      Thread.new do
        loop do
          begin
            rawtext, address = @socket.recvfrom(65535)
            text = BEncode.load(rawtext)

            @logger.debug "Received message #{rawtext} and decoded to #{text}"
            process(text, address)
          rescue => ex
            @logger.error ex.message
            @logger.error ex.backtrace.join("\n")
          end
        end
      end
    end

    def process(message_object, address)
      queries = ['announce_peer', 'get_peers'] # for now, not response to 'find_nodes'

      @logger.debug "received query message #{message_object} and address is #{address.inspect}" if message_object['q'] and (message_object['y'] != 'r')

      # will only process announce_peer and get_peers query for now, ignore anything else
      if queries.include? message_object['q']
        send("process_#{message_object['q']}_message".to_sym, message_object, address)
      elsif message_object['y'] == 'r' and message_object['r'].has_key?('nodes')
        process_find_nodes_response(message_object)
      else 
        # ignore message
      end
    end

    def process_announce_peer_message(msg_object, address)
      @logger.info "processing announce_peer message #{msg_object.inspect} from #{address[3]}:#{address[1]}"
      tid = msg_object['t']
      info_hash = msg_object['a']['info_hash'].force_encoding('ASCII-8BIT')
      token = msg_object['a']['token']
      implied_port = msg_object['a']['implied_port']
      port = msg_object['a']['port']
      remote_node_id = msg_object['a']['id'].force_encoding('ASCII-8BIT')

      resp_body = {
        'id' => create_fake_node_id(@node_id, remote_node_id)
      }

      say_ok(tid, resp_body, address, true)
      # this event should be noted and downloading operation should be done
      # TODO: preprocessing port information according to implied_port
      add_metadata_task(info_hash, address[3], address[1], 'announce_peer')
    end

    def process_get_peers_message(msg_object, address)
      @logger.info "processing get_peers message #{msg_object.inspect} from #{address[3]}:#{address[1]}"
      tid = msg_object['t']
      info_hash = msg_object['a']['info_hash'].force_encoding('ASCII-8BIT')

      token = info_hash[0,8]

      resp_body = {
        'id'    => create_fake_node_id(@node_id, info_hash),
        'nodes' => '',
        'token' => token
      }

      say_ok(tid, resp_body, address, true)
      # this event should be noted
      add_metadata_task(info_hash, address[3], address[1], 'get_peers')
    end

    def process_find_nodes_message(msg_object, address)
      @logger.info "processing find_nodes message #{msg_object.inspect}"
      # extract tid and build response body
      tid = msg_object['t']
      querying_node_id = msg_object['a']['id']

      resp_body = {
        'id'    => create_fake_node_id(@node_id, querying_node_id.force_encoding('ASCII-8BIT')),
        'nodes' => ''
      }

      say_ok(tid, resp_body, address)
    end

    def process_find_nodes_response(msg_object)
      @logger.debug "processsing find_nodes response #{msg_object.inspect} of which length is #{msg_object['r']['nodes'].length} "

      resp_nodes = decode_nodes_string(msg_object['r']['nodes'])
      resp_nodes.each do |resp_node|
        @logger.debug "Adding new KadNode #{resp_node['ip']}:#{resp_node['port']}"
        @nodes << KadNode.new(resp_node['node_id'], resp_node['ip'], resp_node['port']) if resp_node['ip'] != '222.153.184.48'
      
        # debuging
        #@set << resp_node['ip'] if resp_node['ip'] != '222.153.184.48'
      end
    end

    def add_metadata_task(info_hash, ip, port, type)
      peer = Peer.new(ip, port)
      metadata = Metadata.new(info_hash, peer, type)
      @queue << metadata
    end

    def say_ok(tid, resp_body, address, debugging = false)
      send_krpc_message(response_ok(tid, resp_body), address[3], address[1], debugging)
    end

    def send_krpc_message(message, target_ip, target_port, debugging = false)
      begin
        @logger.info "Sending out message #{message.inspect} to #{target_ip}:#{target_port}" if debugging
        @socket.send(message.bencode, 0, target_ip, target_port)
      rescue => ex
        @logger.error "Tried to send to #{target_ip}:#{target_port}"
        @logger.error ex.message
        @logger.error ex.backtrace.join("\n")
      end 
    end
  end
end