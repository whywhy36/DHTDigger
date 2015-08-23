#!/bin/bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
pushd "$DIR/.."
echo "jump to `pwd`"
bundle install
bundle exec ruby db_test.rb
popd