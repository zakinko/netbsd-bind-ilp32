#!/bin/sh
# base の libisc と libdns を /usr/src から建て、libdns を /usr/lib に入れ替える。
#
#   sh build.sh plain     当て物なしで建てる (足場が元の動きを再現するかの対照)
#   sh build.sh patched   bind-ilp32.diff を当てて建て直す
#
# libdns の LIBDPLIBS が libisc の objdir を指すので、libisc も建てる。
# src は動いている版の src.tgz から bind と、その header が要る libuv と
# userspace-rcu だけを取り出す。

set -eu
PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH
MODE=$1
REL=$(uname -r)
SRC=/usr/src
J=$(sysctl -n hw.ncpu)

if [ ! -d $SRC/external/mpl/bind ]; then
	df -h /
	ftp -V -o /root/src.tgz \
	    https://cdn.NetBSD.org/pub/NetBSD/NetBSD-$REL/source/sets/src.tgz
	# src.tgz の CVS/Root は CVS/LinkRoot への hard link で、取り出す範囲に
	# 元が無いと tar がエラーで終わる。CVS は要らないので外す。
	(cd / && tar -xzf /root/src.tgz --exclude CVS \
	    usr/src/external/mpl/bind \
	    usr/src/external/mit/libuv \
	    usr/src/external/lgpl2/userspace-rcu)
	rm -f /root/src.tgz
	df -h /
fi

if [ $MODE = patched ]; then
	(cd $SRC && patch -p1 < /root/t/bind-ilp32.diff)
	grep -n -A2 'define ISC_ZONE_SET(z, f, o)' \
	    $SRC/external/mpl/bind/dist/lib/dns/zone.c
fi

M="make NETBSDSRCDIR=$SRC USETOOLS=no MKDOC=no MKLINT=no MKPROFILE=no MKDEBUGLIB=no MKSTATICLIB=no -j$J"
(cd $SRC/external/mpl/bind/lib/libisc && $M dependall)
(cd $SRC/external/mpl/bind/lib/libdns && $M dependall)

cd $SRC/external/mpl/bind/lib/libdns
SO=$(ls libdns.so.*.* | head -1)
[ -f /usr/lib/$SO ] || { echo "!! /usr/lib/$SO が無い。名前が違う"; ls -l /usr/lib/libdns.so*; exit 1; }
cp /usr/lib/$SO /root/$SO.orig 2>/dev/null || true
install -m 444 $SO /usr/lib/$SO
md5 $SO /usr/lib/$SO
