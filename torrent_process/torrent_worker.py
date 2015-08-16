# encoding: utf-8
import hashlib
import libtorrent
import redis
import uuid
import os
import random
import threading
import traceback
import socket
import time
import datetime
import json
from hashlib import sha1
from random import randint
from struct import unpack
from socket import inet_ntoa
from threading import Thread
from bencode import bencode, bdecode

'''
This component is inspired by https://github.com/78/ssbc/blob/master/workers/ltMetadata.py, 
from which some code pieces are borrowed.
'''
class TorrentWorker(Thread):

    def __init__(self, name, config):
        Thread.__init__(self)
        self.name = name
        self.redis = redis.StrictRedis(host='192.168.1.101', port=6379, db=11)
        self.queue = 'list_name_announce_peer'
        self.storage = 'metadata'
        self.timeout = 60

    def run(self):
        self.setup_workspace()
        while True:
            message = self.redis.brpop(self.queue)
            bencoded_metadata = message[1]
            print bencoded_metadata
            if not self.process(bdecode(bencoded_metadata)):
                self.redis.lpush(self.queue, message)


    def setup_workspace(self):
        workspace_name = "/tmp/dht_worker/" + self.name + "_" + str(uuid.uuid4())[:8] + "/"
        if not os.path.exists(os.path.dirname(workspace_name)):
            os.makedirs(os.path.dirname(workspace_name))

        self.workspace = workspace_name


    def process(self, metadata):
        try:
            session = libtorrent.session()
            r = random.randrange(6000, 10000)
            session.listen_on(r, r+10)
            session.add_dht_router('router.bittorrent.com',6881)
            session.add_dht_router('router.utorrent.com',6881)
            session.add_dht_router('dht.transmission.com',6881)
            session.start_dht()

            content = self.download_and_parse_torrent(session, metadata["info_hash"].encode ('hex'))
            
            session = None

            if content:
                self.redis.rpush(self.storage, content)
                return True

            return False
        except:
            traceback.print_exc()
            return False


    def download_and_parse_torrent(self, session, info_hash):
        info_hash = info_hash.upper()
        magnet_uri = 'magnet:?xt=urn:btih:%s' % info_hash

        try:
            parameters = {
                'auto_managed' : True,
                'duplicate_is_error' : True,
                'paused' : False,
                'save_path' : self.workspace,
                'storage_mode' : libtorrent.storage_mode_t(2)
            }
            handle = libtorrent.add_magnet_uri(session, magnet_uri, parameters)

        except:
            return None

        s = session.status()

        handle.set_sequential_download(1)
        torrent_content = None

        downloaded_torrent_path = None
        print 'Trying to download' + magnet_uri
        for i in xrange(0, self.timeout):
            if handle.has_metadata():
                print 'Download started ...'
                info = handle.get_torrent_info()
                torrent_file = libtorrent.create_torrent(info)
                downloaded_torrent_path = self.workspace + info.name()
                with open(downloaded_torrent_path, "wb") as f:
                    f.write(libtorrent.bencode(torrent_file.generate()))
                torrent_content = info.metadata()
                print 'Download finished and saved it to %s' % downloaded_torrent_path
                break
            print 'Retrying in 1 second'
            time.sleep(1)


        if downloaded_torrent_path and os.path.exists(downloaded_torrent_path):
            os.system('mv "%s" "%s"' % (downloaded_torrent_path, downloaded_torrent_path + '.parsed'))
        session.remove_torrent(handle)

        torrent_info = self.parse_torrent_content(torrent_content)

        return torrent_info

    # borrowed
    def decode(self, s):
        if type(s) is list:
            s = ';'.join(s)
        u = s
        for x in (self.encoding, 'utf8', 'gbk', 'big5'):
            try:
                u = s.decode(x)
                return u
            except:
                pass
        return s.decode(self.encoding, 'ignore')

    # borrowed
    def decode_utf8(self, d, i):
        if i+'.utf-8' in d:
            return d[i+'.utf-8'].decode('utf8')
        return self.decode(d[i])

    # borrowed
    def parse_torrent_content(self, torrent_content):
        info = {}
        self.encoding = 'utf8'
        try:
            torrent = bdecode(torrent_content)
            if not torrent.get('name'):
                return None
        except:
            return None
        try:
            info['create_time'] = datetime.datetime.fromtimestamp(float(torrent['creation date'])).strftime("%Y-%m-%d %H:%M:%S")
        except:
            info['create_time'] = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        if torrent.get('encoding'):
            self.encoding = torrent['encoding']
        if torrent.get('announce'):
            info['announce'] = self.decode_utf8(torrent, 'announce')
        if torrent.get('comment'):
            info['comment'] = self.decode_utf8(torrent, 'comment')[:200]
        if torrent.get('publisher-url'):
            info['publisher-url'] = self.decode_utf8(torrent, 'publisher-url')
        if torrent.get('publisher'):
            info['publisher'] = self.decode_utf8(torrent, 'publisher')
        if torrent.get('created by'):
            info['creator'] = self.decode_utf8(torrent, 'created by')[:15]

        if 'info' in torrent:
            detail = torrent['info'] 
        else:
            detail = torrent
        info['name'] = self.decode_utf8(detail, 'name')
        if 'files' in detail:
            info['files'] = []
            for x in detail['files']:
                if 'path.utf-8' in x:
                    v = {'path': self.decode('/'.join(x['path.utf-8'])), 'length': x['length']}
                else:
                    v = {'path': self.decode('/'.join(x['path'])), 'length': x['length']}
                if 'filehash' in x:
                    v['filehash'] = x['filehash'].encode('hex')
                info['files'].append(v)
            info['length'] = sum([x['length'] for x in info['files']])
        else:
            info['length'] = detail['length']
        info['data_hash'] = hashlib.md5(detail['pieces']).hexdigest()
        if 'profiles' in detail:
            info['profiles'] = detail['profiles']

        return json.dumps(info, ensure_ascii=False)

if __name__ == "__main__":
    socket.setdefaulttimeout(30)
    worker = TorrentWorker("testing", "")
    worker.start()




