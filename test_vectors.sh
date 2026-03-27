#!/bin/sh
set -u

SERVER="${SERVER:-127.0.0.1}"
PORT="${PORT:-53}"
DIG_BIN="${DIG_BIN:-dig}"

pass=0
fail=0

run_test() {
  domain="$1"
  expected="$2"

  # +short returns one address or nothing; trim CR just in case.
  actual="$($DIG_BIN @${SERVER} -p ${PORT} AAAA "$domain" +short 2>/dev/null | tr -d '\r' | head -n 1)"

  if [ "$actual" = "$expected" ]; then
    printf 'PASS  %-34s -> %s\n' "$domain" "$actual"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-34s expected=%s got=%s\n' "$domain" "$expected" "${actual:-<empty>}"
    fail=$((fail + 1))
  fi
}

echo "Testing v6.alt resolver at ${SERVER}:${PORT}"
echo

run_test 'eaaq3o-e.v6.alt'                    '2001:db8::1'
run_test 'ai-e.v6.alt'                        '200::1'
run_test 'aiamvog6wthgaq3cisjokoiewu.v6.alt'  '200:cab8:deb4:ce60:4362:4492:e539:4b5'
run_test 'a-e.v6.alt'                         '::1'
run_test 'a-a.v6.alt'                         '::'
run_test '72-e.v6.alt'                        'fe80::1'
run_test '77777777777777777777777774.v6.alt'  'ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'
run_test 'ceiqaaaaaairc-rce.v6.alt'           '1111:0:0:1111::1111'
run_test 'ceiq-eiraaaaaaarce.v6.alt'          '1111::1111:0:0:1111'
//run_test 'ceiq-eiraaaaaaarce.v6.alt'          '1111:0:0:0:1111::1111'

echo
printf 'Summary: %d passed, %d failed\n' "$pass" "$fail"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
