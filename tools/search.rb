require 'sequel'
require 'yaml'
require 'logger'

# usage: xxx keyword

module DHTDigger
  module Tools
    class Search

      def initialize
        postgres_config = YAML.load_file("#{File.dirname(__FILE__)}/../configuration/config.yml")['postgres']

        @db = Sequel.postgres(:host     => postgres_config['host'],
                              :port     => postgres_config['port'],
                              :database => postgres_config['database'],
                              :user     => postgres_config['username'],
                              :password => postgres_config['password'])
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
        @db.loggers << @logger
      end

      def search(keyword)
        #results = @db.fetch("select name from ( select * from torrents, plainto_tsquery(?) as q where (tsv @@ q)) as t1;", keyword)
        #results = @db.fetch("select name from torrents where tsv @@ plainto_tsquery(?)", keyword)
        dataset = @db[:torrents]
        results = dataset.where('tsv @@ plainto_tsquery(?)', keyword)
        puts "results contain #{results.count} items"
        results.each {|item| puts item[:name] }
      end
    end
  end
end

DHTDigger::Tools::Search.new.search(ARGV[0])

