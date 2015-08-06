# encoding: utf-8
import libtorrent
import redis
import uuid
import os
import random
import threading
import traceback
import socket
from threading import Thread
from bencode import bencode, bdecode

class TorrentWorker(Thread):

    def __init__(self, name, config):
        Thread.__init__(self)
        self.name = name
        self.redis = redis.StrictRedis(host='192.168.1.101', port=6379, db=11)
        self.queue = 'list_name'

    def run(self):
        self.setup_workspace()
        while True:
            bencoded_metadata = self.redis.brpop(self.queue)[1]
            print bencoded_metadata
            self.process(bdecode(bencoded_metadata))

    def setup_workspace(self):
        workspace_name = "/tmp/dht_worker/" + self.name + "_" + str(uuid.uuid4())[:8]
        if not os.path.exists(os.path.dirname(workspace_name)):
            os.makedirs(os.path.dirname(workspace_name))

        self.workspace = workspace_name


    def process(self, metadata):
        print metadata
        try:
            session = libtorrent.session()
            r = random.randrange(10000, 50000)
            session.listen_on(r, r+10)
            session.add_dht_router('router.bittorrent.com',6881)
            session.add_dht_router('router.utorrent.com',6881)
            session.add_dht_router('dht.transmission.com',6881)
            session.add_dht_router('127.0.0.1',6881)
            session.start_dht()

            session = None
        except:
            traceback.print_exc()



if __name__ == "__main__":
    socket.setdefaulttimeout(30)
    worker = TorrentWorker("testing", "")
    worker.start()




