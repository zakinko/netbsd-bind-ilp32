#!/bin/sh
# base の libisc と libdns を /usr/src から建て、/usr/lib のものと入れ替える。
#
#   sh build.sh plain     当て物なしで建てる (足場が元の動きを再現するかの対照)
#   sh build.sh patched [diff]   diff (既定 bind-ilp32.diff) を当てて建て直す
#
# libdns の LIBDPLIBS が libisc の objdir を指すので、libisc も建てる。
# src は動いている版の src.tgz から bind と、その header が要る libuv と
# userspace-rcu だけを取り出す。

set -eu
PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH
MODE=$1
DIFF=${2:-bind-ilp32.diff}
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
	(cd $SRC && patch -f -p1 -i /root/t/$DIFF </dev/null)
	grep -n -A2 'define ISC_ZONE_SET(z, f, o)' \
	    $SRC/external/mpl/bind/dist/lib/dns/zone.c
fi

# DPADD は依存の追跡にしか使われない。src の全体は取り出していないので、
# libpthread などの obj を探しに行かないよう空にする。link は LDADD が行う。
M="make NETBSDSRCDIR=$SRC USETOOLS=no DPADD= MKDOC=no MKLINT=no MKPROFILE=no MKDEBUGLIB=no MKSTATICLIB=no -j$J"
# libisc は libuv を libuv_pic.a から static に取り込むので、先に建てる。
(cd $SRC/external/mit/libuv/lib && $M dependall)
(cd $SRC/external/mpl/bind/lib/libisc && $M dependall)
(cd $SRC/external/mpl/bind/lib/libdns && $M dependall)

for l in isc dns; do
	cd $SRC/external/mpl/bind/lib/lib$l
	SO=$(ls lib$l.so.*.* | head -1)
	[ -f /usr/lib/$SO ] || { echo "!! /usr/lib/$SO が無い。名前が違う"; ls -l /usr/lib/lib$l.so*; exit 1; }
	install -m 444 $SO /usr/lib/$SO
	md5 $SO /usr/lib/$SO
done
