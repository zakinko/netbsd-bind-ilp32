#!/bin/sh
# NetBSD 11.1/i386 の base の libdns を、ISC_ZONE_SET/CLR の書き戻しを直した
# ものに入れ替える (PR bin/59982, bin/60833)。
#
#   sh install-libdns.sh            入れ替える
#   sh install-libdns.sh restore    元に戻す
#
# 入れ替える前に、いまの /usr/lib/libdns.so.26.0 が 11.1/i386 の配布物と
# 同じものかを md5 で確かめ、違えば何もしない。元のファイルは
# /usr/lib/libdns.so.26.0.orig に残す。named の再起動はしない。

set -eu
PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH

BASE=${BASE:-https://github.com/zakinko/netbsd-bind-ilp32/releases/download/netbsd-11.1-i386}
LIB=/usr/lib/libdns.so.26.0
STOCK=0f88f9c91fa49785fae80a85a3c9357d
FIXED=@FIXED@

sum() { md5 "$1" | sed 's/.* = //'; }

[ "$(id -u)" = 0 ] || { echo "root で動かしてください"; exit 1; }

if [ "${1:-}" = restore ]; then
	[ -f $LIB.orig ] || { echo "$LIB.orig がありません"; exit 1; }
	[ "$(sum $LIB.orig)" = $STOCK ] || { echo "$LIB.orig が配布物と違うので戻しません"; exit 1; }
	install -m 444 $LIB.orig $LIB
	rm -f $LIB.orig
	echo "元に戻しました。named を再起動してください。"
	exit 0
fi

case "$(uname -m) $(uname -r)" in
"i386 11.1") ;;
*) echo "NetBSD 11.1/i386 用です ($(uname -m) $(uname -r))"; exit 1 ;;
esac

cur=$(sum $LIB)
if [ $cur = $FIXED ]; then
	echo "もう入れ替えてあります。"
	exit 0
fi
[ $cur = $STOCK ] || { echo "$LIB が 11.1 の配布物と違うので入れ替えません ($cur)"; exit 1; }

T=$(mktemp -d /tmp/libdns.XXXXXX)
trap 'rm -rf $T' EXIT
ftp -V -o $T/libdns.so.26.0 $BASE/libdns.so.26.0
[ "$(sum $T/libdns.so.26.0)" = $FIXED ] || { echo "取ってきたファイルの md5 が違います"; exit 1; }

cp -p $LIB $LIB.orig
install -m 444 $T/libdns.so.26.0 $LIB
echo "入れ替えました。named を再起動してください。"
echo "元に戻すとき: sh install-libdns.sh restore"
