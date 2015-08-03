# encoding: utf-8

require 'socket'
require 'bencode'
require 'logger'
require 'eventmachine'
require 'pry'
require_relative 'krpc'

module DHTDigger::Digger

  class MetadataProcessor
    def initialize(queue, logger)
      @queue = queue
      @logger = logger
    end

    def run
      loop {
        metadata = @queue.pop
        process(metadata)
      }
    end

    def process(metadata)
      @logger.info "process metadata: #{metadata.inspect}"
      # TODO
      # parse metadata and store it in database
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

      # TODO: replace '100' with some configuration related variable
      # This is a queue for KadNode
      @nodes = SizedQueue.new(10000)


      # For information
      #@set = Set.new
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
      puts "@nodes' size is #{@nodes.size}"
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
      prefix = local_node_id.force_encoding('ASCII-8BIT')[0, 10]
      postfix = remote_node_id.force_encoding('ASCII-8BIT')[10, 10]

      (prefix + postfix).force_encoding('ASCII-8BIT')
    end

    def start_workers(count=5)
      @logger.info "starting worker"
      @queue = Queue.new if @queue.nil?
      count.times do |i|
        worker_name = "worker_#{i}"
        Thread.new do
          @logger.info "starting worker #{worker_name}"
          worker = MetadataProcessor.new(@queue)
          worker.run
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
          rescue
            # TODO: logging sth and go ahead
          end
        end
      end
    end

    def process(message_object, address)
      queries = ['announce_peer', 'get_peers']

      # will only process announce_peer and get_peers query for now, ignore anything else
      if queries.include? message_object['q']
        queries.send(message_object['q'], message_object, address)
      elsif message_object['y'] == 'r' and message_object['r'].has_key?('nodes')
        process_find_nodes_response(message_object)
      else 
        # ignore message
      end
    end

    def process_announce_peer_message(msg_object, address)
      @logger.info "processing announce_peer message #{msg_object.inspect}"
      # TODO: enqueue the message, response with OK message
    end

    def process_get_peers_message(msg_object, address)
      @logger.info "processing get_peers message #{msg_object.inspect}"
      # TODO: response with OK message, do nothing for now
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

    def send_krpc_message(message, target_ip, target_port)
      begin
        @logger.debug "Sending out KRPC message to #{target_port}:#{target_port}"
        @socket.send(message.bencode, 0, target_ip, target_port)
      rescue => ex
        @logger.error "Tried to send to #{target_ip}:#{target_port}"
        @logger.error ex.message
        @logger.error ex.backtrace.join("\n")
      end 
    end
  end
end