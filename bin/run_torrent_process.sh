#!/bin/bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
pushd "$DIR/../torrent_process"
echo "jump to `pwd`"
python torrent_worker.py
popd