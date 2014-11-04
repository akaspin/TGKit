#!/bin/sh

# Copyright 2014 Paul Eipper
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


SOURCE_DIR="tg"
TARGET_DIR="../libtgl"

TG_FILES="
LICENSE
auto/auto-header.h
auto/auto.c
auto/constants.h
auto-static.c
auto.h
binlog.c
binlog.h
include.h
loop.c
loop.h
mtproto-client.c
mtproto-client.h
mtproto-common.c
mtproto-common.h
net.c
net.h
no-preview.h
queries.c
queries.h
server.pub
structures.c
structures.h
tgl-fetch.h
tgl-inner.h
tgl-layout.h
tgl-timers.h
tgl-timers.c
tgl.c
tgl.h
tools.c
tools.h
tree.h
updates.c
updates.h
"

TG_SUBDIRS="
auto
"

TG_TOUCH="
config.h
"

CFLAGS="-I/opt/local/include"
LDFLAGS="-L/opt/local/lib"

###########################################################################

set -e

cd "`dirname \"$0\"`"
CURRENTPATH=$(pwd)

for SUBDIR in $TG_SUBDIRS; do
    mkdir -p "${CURRENTPATH}/${TARGET_DIR}/${SUBDIR}"
done

SRCROOT=$(cd ${CURRENTPATH}/${SOURCE_DIR}; pwd)
DSTROOT=$(cd ${CURRENTPATH}/${TARGET_DIR}; pwd)

cd ${SRCROOT}
CFLAGS=${CFLAGS} LDFLAGS=${LDFLAGS} ./configure --disable-liblua --disable-libconfig
make create_dirs_and_headers

for FILE in ${TG_FILES}; do
    cp "${FILE}" "${DSTROOT}/${FILE}"
done

for TOUCH in ${TG_TOUCH}; do
    touch "${DSTROOT}/${TOUCH}"
done
