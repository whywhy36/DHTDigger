# DHTDigger
Another wiretap in DHT network.

If deployed properly, DHTDigger could capture as many DHT messages as it can, 
and queue them in Redis. Another torrent worker will process all queued messages 
by downloading and parsing torrents. All metadata parsed from torrents will be stored in 
another Redis queue for further processing (ie. feeding one BT search engine or 
data mining task). 

### Components
- wiretap
- torrent_worker

### Configuration
Configuration file sits in confiuration folder, replace all [placeholder] with your 
real environment info. One sample is config.yml.example.

### Usage

Both of them can be started by running shell script under bin folder, 
```
bin\run_digger.sh
```
and 
```
bin\run_torrent_process.sh
```

###Other

To make sure the whole system running well without our attendence, it's suggest to use 
monitoring tools (like [monit](https://mmonit.com/monit/)). Here's one example used in my 
Ubuntu 14.04 with Monit Version 5.6.

```
check process dhtdigger with pidfile /path/to/my/pid/file
	start program = "/path/to/my/run_digger.sh"
	stop program = "/bin/cat /path/to/my/pid/file | xargs /bin/kill"
	group dhtdigger
```

###License
MIT




