#!/bin/sh
set -u

SERVER="${SERVER:-127.0.0.1}"
PORT="${PORT:-53}"
DIG_BIN="${DIG_BIN:-dig}"
V6ALT_BIN="${V6ALT_BIN:-./v6alt}"

pass=0
fail=0

run_test() {
  domain="$1"
  expected="$2"

  actual="$($DIG_BIN @${SERVER} -p ${PORT} AAAA "$domain" +short 2>/dev/null | tr -d '\r' | head -n 1)"

  if [ "$actual" = "$expected" ]; then
    printf 'PASS  dns %-30s -> %s\n' "$domain" "$actual"
    pass=$((pass + 1))
  else
    printf 'FAIL  dns %-30s expected=%s got=%s\n' "$domain" "$expected" "${actual:-<empty>}"
    fail=$((fail + 1))
  fi
}

run_reverse_test() {
  ip="$1"
  expected="$2"

  actual="$($V6ALT_BIN "$ip" 2>/dev/null | tr -d '\r' | head -n 1)"

  if [ "$actual" = "$expected" ]; then
    printf 'PASS  rev %-30s -> %s\n' "$ip" "$actual"
    pass=$((pass + 1))
  else
    printf 'FAIL  rev %-30s expected=%s got=%s\n' "$ip" "$expected" "${actual:-<empty>}"
    fail=$((fail + 1))
  fi
}

run_roundtrip_test() {
  domain="$1"

  ip="$($DIG_BIN @${SERVER} -p ${PORT} AAAA "$domain" +short 2>/dev/null | tr -d '\r' | head -n 1)"
  if [ -z "${ip}" ]; then
    printf 'FAIL  rtt %-30s resolver returned empty result\n' "$domain"
    fail=$((fail + 1))
    return
  fi

  actual="$($V6ALT_BIN "$ip" 2>/dev/null | tr -d '\r' | head -n 1)"

  if [ "$actual" = "$domain" ]; then
    printf 'PASS  rtt %-30s -> %s -> %s\n' "$domain" "$ip" "$actual"
    pass=$((pass + 1))
  else
    printf 'FAIL  rtt %-30s expected=%s got=%s (ip=%s)\n' "$domain" "$domain" "${actual:-<empty>}" "$ip"
    fail=$((fail + 1))
  fi
}

echo "Testing v6.alt resolver at ${SERVER}:${PORT}"
echo "Using converter: ${V6ALT_BIN}"
echo

if [ ! -x "$V6ALT_BIN" ]; then
  echo "ERROR: v6alt binary not found or not executable: $V6ALT_BIN" >&2
  echo "Build it first, for example: make v6alt" >&2
  exit 2
fi

run_test 'eaaq3o-e.v6.alt'                    '2001:db8::1'
run_test 'ai-e.v6.alt'                        '200::1'
run_test 'aiamvog6wthgaq3cisjokoiewu.v6.alt'  '200:cab8:deb4:ce60:4362:4492:e539:4b5'
run_test 'a-e.v6.alt'                         '::1'
run_test 'a-a.v6.alt'                         '::'
run_test '72-e.v6.alt'                        'fe80::1'
run_test '77777777777777777777777774.v6.alt'  'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
run_test 'ceiqaaaaaairc-rce.v6.alt'           '1111:0:0:1111::1111'
run_test 'ceiq-eiraaaaaaarce.v6.alt'          '1111::1111:0:0:1111'

echo
echo "Testing reverse conversion with v6alt"
echo

run_reverse_test '2001:db8::1'                          'eaaq3o-e.v6.alt'
run_reverse_test '200::1'                              'ai-e.v6.alt'
run_reverse_test '200:cab8:deb4:ce60:4362:4492:e539:4b5' 'aiamvog6wthgaq3cisjokoiewu.v6.alt'
run_reverse_test '::1'                                 'a-e.v6.alt'
run_reverse_test '::'                                  'a-a.v6.alt'
run_reverse_test 'fe80::1'                             '72-e.v6.alt'
run_reverse_test 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff' '77777777777777777777777774.v6.alt'
run_reverse_test '1111:0:0:1111::1111'                 'ceiqaaaaaairc-rce.v6.alt'
run_reverse_test '1111::1111:0:0:1111'                 'ceiq-eiraaaaaaarce.v6.alt'

echo
echo "Testing DNS -> IP -> v6.alt roundtrip"
echo

run_roundtrip_test 'eaaq3o-e.v6.alt'
run_roundtrip_test 'ai-e.v6.alt'
run_roundtrip_test 'aiamvog6wthgaq3cisjokoiewu.v6.alt'
run_roundtrip_test 'a-e.v6.alt'
run_roundtrip_test 'a-a.v6.alt'
run_roundtrip_test '72-e.v6.alt'
run_roundtrip_test '77777777777777777777777774.v6.alt'
run_roundtrip_test 'ceiqaaaaaairc-rce.v6.alt'
run_roundtrip_test 'ceiq-eiraaaaaaarce.v6.alt'

echo
printf 'Summary: %d passed, %d failed\n' "$pass" "$fail"

if [ "$fail" -ne 0 ]; then
  exit 1
fi