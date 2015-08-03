# encoding: utf-8

require 'ipaddr'
require 'json'
require 'digest'

module DHTDigger::Digger
  module KRPC

    def random_string(length)
      ret = length.times.inject([]) { |ret, _| ret << rand(0..255) }
      format = 'c' * length
      ret.pack(format)
    end

    # generate a random node id
    def random_node_id
      Digest::SHA1.digest(random_string(20))
    end

    # generate a transaction id
    def generate_tid
      random_string(2)
    end

    def decode_nodes_string(nodes_string)
      nodes_string = nodes_string.force_encoding('ASCII-8BIT')

      nodes = []
      return nodes if (nodes_string.size % 26 != 0)

      iteration = nodes_string.length / 26

      logger.debug "iteration is #{iteration}"

      iteration.times do |i|
        string_slice = nodes_string[26*i, 26]
        node_id_string = string_slice[0, 20]
        ip_string = string_slice[20, 4]
        port_string = string_slice[24, 2]

        ip = IPAddr.ntop(ip_string)
        port = port_string.unpack('n').first # refer to http://apidock.com/ruby/String/unpack

        logger.debug "node id is #{node_id_string}, uri is #{ip}:#{port}"
        nodes << {'node_id' => node_id_string, 'ip' => ip, 'port' => port}
      end
      nodes
    end

    def find_node(nid, target_nid)
      query_body = {
        'id'     => nid,
        'target' => target_nid
      }

      query_message(__method__, query_body)
    end

    def ping(nid)
      query_body = {
        'id' => nid
      }

      query_message(__method__, query_body)
    end

    def get_peers(nid, infohash)
      query_body = {
        'id'       => nid,
        'infohash' => infohash
      }

      query_message(__method__, query_body)
    end

    def announce_peers(nid)
      query_body = {
        'id'           => nid,
        'implied_port' => '',
        'port'         => '',
        'token'        => ''
      }

      query_message(__method__, query_body)
    end

    def query_message(query_type, query_body)
      {
        't' => generate_tid,
        'y' => 'q',
        'q' => query_type.to_s,
        'a' => query_body
      }
    end

    def response_ok(tid, resp_body)
      {
        't' => tid,
        'y' => 'r',
        'r' => resp_body
      }
    end

    def response_error(tid)
      {
        't' => tid,
        'y' => 'e',
        'e' => [201, "A General Error Ocurred"]
      }
    end
  end
end