require 'sequel'

module DHTDigger
  module Diggers
    class DBOps
      def initialize
        @redis = ''
        @db = Sequel.postgres(:host => '192.168.1.101', :database => 'torrents',
                              :user => 'postgres', :password => '')
      end

      def run

      end
    end
  end
end