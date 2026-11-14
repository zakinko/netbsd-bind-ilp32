#!/bin/sh
# primary と secondary の named を一つずつ立て、secondary にゾーンを転送させる。
#
#   sh repro.sh <label>
#
# 最後に "RESULT <label>: completed|crashed|exited|timeout" を出す。
# どちらの named も、いま /usr/lib に入っている libdns で動く。

set -u
PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH
L=$1
W=/tmp/repro-$L
rm -rf $W
mkdir -p $W/p $W/s

for a in 127.0.0.2 127.0.0.3; do
	ifconfig lo0 inet alias $a/32 2>/dev/null || true
done

{
	printf '$TTL 300\n'
	printf '@ IN SOA ns.example.test. root.example.test. 1 3600 600 86400 300\n'
	printf '@ IN NS ns.example.test.\n'
	printf 'ns IN A 127.0.0.2\n'
	i=1
	while [ $i -le 200 ]; do
		printf 'h%d IN A 192.0.2.%d\n' $i $((i % 250 + 1))
		i=$((i + 1))
	done
} > $W/p/example.test.db

cat > $W/p/named.conf <<EOF
options {
	directory "$W/p";
	pid-file "$W/p/named.pid";
	listen-on port 53 { 127.0.0.2; };
	listen-on-v6 { none; };
	recursion no;
	allow-transfer { any; };
	notify explicit;
	also-notify { 127.0.0.3; };
};
controls { };
zone "example.test" { type primary; file "example.test.db"; };
EOF

cat > $W/s/named.conf <<EOF
options {
	directory "$W/s";
	pid-file "$W/s/named.pid";
	listen-on port 53 { 127.0.0.3; };
	listen-on-v6 { none; };
	recursion no;
	notify no;
	transfer-source 127.0.0.3;
	statistics-file "$W/s/named.stats";
};
include "/etc/rndc.key";

controls { inet 127.0.0.3 port 953 allow { 127.0.0.3; 127.0.0.1; } keys { rndc-key; }; };
zone "example.test" {
	type secondary;
	primaries { 127.0.0.2; };
	file "example.test.bk";
};
EOF

[ -f /etc/rndc.key ] || rndc-confgen -a -c /etc/rndc.key
echo "== libisc and libdns in use"
md5 /usr/lib/libisc.so.*.* /usr/lib/libdns.so.*.* 2>/dev/null

/usr/sbin/named -g -c $W/p/named.conf > $W/p.log 2>&1 &
PPID_=$!
sleep 3
/usr/sbin/named -g -c $W/s/named.conf > $W/s.log 2>&1 &
SPID=$!

r=timeout
n=0
while [ $n -lt 360 ]; do
	if grep -q 'Transfer completed' $W/s.log; then r=completed; break; fi
	if grep -q -E 'assertion|INSIST' $W/s.log; then r=crashed; break; fi
	if ! kill -0 $SPID 2>/dev/null; then r=exited; break; fi
	if [ $n = 10 ]; then
		# 起動直後に送った NOTIFY を secondary が取りこぼしていても転送が始まるように、
		# serial を上げて primary に読み直させ、もう一度 NOTIFY を出させる。
		sed -i 's/ 1 3600 600/ 2 3600 600/' $W/p/example.test.db
		kill -HUP $PPID_
	fi
	sleep 1
	n=$((n + 1))
done
sleep 2

if [ $r = completed ]; then
	# primary の serial を上げて読み直させ、secondary に NOTIFY が届くかを見る。
	# 届けば secondary は serial 3 を取りに来る。bin/60833 と同じ経路。
	sed -i 's/ [12] 3600 600/ 3 3600 600/' $W/p/example.test.db
	kill -HUP $PPID_
	n=0
	while [ $n -lt 30 ]; do
		grep -q 'serial 3' $W/s.log && break
		sleep 1
		n=$((n + 1))
	done
	echo "== NOTIFY"
	grep -i -E 'sending notif|notify' $W/p.log | tail -5
	grep -i -E 'notify from|serial 3' $W/s.log | tail -5
	if grep -q 'notify from 127.0.0.2' $W/s.log; then
		echo "NOTIFY $L: received"
	else
		echo "NOTIFY $L: none"
	fi
else
	echo "== NOTIFY (primary)"
	grep -i -E 'sending notif|notify' $W/p.log | tail -5
	echo "NOTIFY $L: primary sent $(grep -c -i 'sending notif' $W/p.log)"
fi

echo "== primary log (tail)"
tail -15 $W/p.log
echo "== secondary log (tail)"
tail -40 $W/s.log
if [ $r = completed ]; then
	echo "== AXFR from the secondary"
	dig +noall +answer @127.0.0.3 example.test AXFR | wc -l
	# 統計 (isc_stats) と histogram (isc_histo) を通る経路を動かして読む。
	i=0
	while [ $i -lt 50 ]; do
		dig +short @127.0.0.3 h$((i % 200 + 1)).example.test A > /dev/null
		i=$((i + 1))
	done
	echo "== rndc stats"
	rndc -k /etc/rndc.key -s 127.0.0.3 -p 953 stats && sleep 1 && \
	    grep -E 'IPv4 requests received|queries resulted in successful answer|transfer requests succeeded|QUERY' $W/s/named.stats | head -10
fi

kill $SPID $PPID_ 2>/dev/null
sleep 2
kill -9 $SPID $PPID_ 2>/dev/null
echo "RESULT $L: $r"
