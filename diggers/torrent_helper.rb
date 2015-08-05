# encoding: utf-8

module DHTDigger::Diggers

  # TorrentHelper will do everything within @workspace which should be
  # defined in class (include this Mixin)
  module  TorrentHelper

    # download one torrent based on the info_hash
    def download_torrent(address, info_hash, timeout = 8)
      # TODO:
    end

    # parse the downloaded torrent and extract all included metadata
    def parse_torrent(torrent_file)

    end

    # delete the downloaded torrent for saving disk space
    def delete_torrent(torrent_file)

    end

    private


  end
end