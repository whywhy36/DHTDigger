require 'sequel'
require 'redis'
require 'yaml'
require 'json'
require 'logger'

module DHTDigger
  module Database
    class DBOps

      def initialize
        @redis = ''
        @config = YAML.load_file("#{File.dirname(__FILE__)}/../configuration/config.yml")


        #puts binding.pry

        postgres_config = @config['postgres']
        redis_config = @config['redis']
        logging_config = @config['logging']
        db_ops_config = @config['db_ops']


        @db = Sequel.postgres(:host     => postgres_config['host'],
                              :port     => postgres_config['port'],
                              :database => postgres_config['database'],
                              :user     => postgres_config['username'],
                              :password => postgres_config['password'])

        @redis = Redis.new(:host => redis_config['host'],
                           :port => redis_config['port'],
                           :db   => redis_config['db'])

        @parsed_torrent_metadata_queue = redis_config['metadata']

        @name = db_ops_config['name']

        @logger = Logger.new("#{logging_config['output']}#{@name}.log")
        @logger.level = Logger::INFO

        # add logger
        @db.loggers << @logger
      end

      def run(&callback)
        loop do
          item_string = @redis.blpop(@parsed_torrent_metadata_queue)[1]
          @logger.info "item_string is #{item_string}"
          next if item_string.nil? or item_string.eql? 'null'
          item = JSON.parse(item_string)

          category = classify_item(item)
          name = item['name']
          data_hash = item['data_hash']
          length = item['length']
          create_time = item['create_time']
          files = item['files']
          magnet_uri = item['magnet_uri'] || ''
          profiles = item['profiles']


          dataset = @db[:torrents]

          record = dataset.where(:data_hash => data_hash)
          if 1 != record.update(:counter=>Sequel.+(:counter, 1))
            torrent = dataset.insert(:name => name,
                           :files => files.to_s,
                           :data_hash => data_hash,
                           :length => length,
                           :category => category,
                           :magnet_uri => magnet_uri,
                           :metadata => item_string,
                           :counter => 1,
                           :created_at => create_time,
                           :updated_at => DateTime.now)
            callback.call(torrent) if callback
          end
        end
      end

      def classify_item(item)

      end
    end
  end
end