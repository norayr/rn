# rn

A small DNS server for `*.v6.alt` names.

It decodes the rightmost label before `.v6.alt` using the Prosody [mod_s2s_v6mesh](https://modules.prosody.im/mod_s2s_v6mesh.html) scheme and returns an `AAAA` record. For ordinary DNS names, it can forward queries to one or more upstream DNS servers. It can also answer reverse IPv6 `PTR` lookups under `ip6.arpa` by converting the IPv6 address back into a `*.v6.alt` hostname.

## Features

- local synthetic `AAAA` answers for `*.v6.alt`
- local synthetic `PTR` answers for IPv6 `ip6.arpa`
- UDP forwarding for other queries
- multiple IPv4 and IPv6 bind addresses
- `listen_mode=local|all`
- file logging, with optional query logging

## Build

Build with:

```sh
make
```

This runs:

```sh
fpc rn.pas
```

## Install

Install the binary, default config file, systemd unit, and OpenRC script:

```sh
sudo make install
```

By default this installs:

- `rn` to `/usr/sbin/rn`
- config to `/etc/rn.conf`
- documentation to `/usr/share/doc/rn`

### Init system integration

Service files are installed separately.

#### OpenRC

The distribution includes `rn.openrc` and installs with `make install-openrc`.

```sh
sudo make install-openrc
```

You can also install it manually, without makefile:

```sh
sudo install -m 755 rn.openrc /etc/init.d/rn
```

Enable it:

```sh
sudo rc-update add rn default
sudo rc-service rn start
```

Check status:

```sh
rc-service rn status
```

#### systemd

```sh
sudo make install-systemd
```

#### FreeBSD

```sh
sudo make install-freebsd
```

This installs the rc script to `/usr/local/etc/rc.d/rn`.

````

## Install on Gentoo

Add [norayr-overlay](https://github.com/norayr/norayr-overlay).

```sh
emerge --sync norayr-overlay
emerge net-dns/rn -av
/etc/init.d/rn start
```

## Manual start

Example:

```sh
./rn 53 1.1.1.1
```

Note: to use ports below 1024, the program needs root privileges.

Expected startup output:

```text
Listening on 127.0.0.1:53
Listening on [::1]:53
Forwarding non-.v6.alt queries to:
  1.1.1.1:53
```

Example with all-interface listening:

```sh
./rn 53 1.1.1.1 8.8.8.8 --listen-all
```

Example with explicit bind addresses:

```sh
./rn 53 1.1.1.1 --bind4=127.0.0.1 --bind6=::1 --bind6=200:ffff::1
```

Note: in config files, multiple addresses are comma-separated.

With `-c`, if no file name is given, `rn` reads `/etc/rn.conf`:

```sh
./rn -c
./rn -c /etc/rn.conf
./rn -c ./rn.conf
```

## Config file

`rn` can be started either with command-line arguments or with an INI-style config file.

Example config:

```ini
[server]
port=53
listen_mode=local
; listen_mode=all

; Explicit bind lists. Comma-separated values are accepted.
; If bind_ipv4 or bind_ipv6 is set, it overrides the default bind list
; for that protocol family only.
; bind_ipv4=127.0.0.1
; bind_ipv4=127.0.0.1, 10.0.0.5
; bind_ipv6=::1
; bind_ipv6=::1, 200:ffff::1

[upstreams]
; Comma-separated list of upstream DNS servers.
; IPv6 with a port must use brackets.
dns=1.1.1.1, 8.8.8.8, [2606:4700:4700::1111]:53

[logging]
file=/var/log/rn.log
queries=false
```

### Listening behavior

`listen_mode=local` means:

- IPv4 binds to `127.0.0.1`
- IPv6 binds to `::1`

`listen_mode=all` means:

- IPv4 binds to `0.0.0.0`
- IPv6 binds to `::`

If only one of `bind_ipv4` or `bind_ipv6` is specified, the other protocol family keeps its default bind list.

Example:

```ini
[server]
listen_mode=local
bind_ipv6=::1, 200:ffff::1
```

This keeps IPv4 on `127.0.0.1` and binds IPv6 on both `::1` and `200:ffff::1`.

For bind addresses, write plain IPs without brackets:

```ini
bind_ipv6=::1, 200:ffff::1
```

Brackets are only for host-and-port syntax, such as upstream entries:

```ini
dns=[2606:4700:4700::1111]:53
```

### Logging

`rn` logs startup messages, bind failures, and other operational messages to stdout/stderr and also appends them to the configured log file.

Config:

```ini
[logging]
file=/var/log/rn.log
queries=true
```

If `queries=true`, incoming queries and local/forwarded handling are logged as well.

## Manual tests

Local `v6.alt` query:

```sh
dig @127.0.0.1 -p 53 AAAA eaaq3o-e.v6.alt
```

Forwarded ordinary DNS query:

```sh
dig @127.0.0.1 -p 53 A gnu.org
```

Reverse IPv6 PTR query:

```sh
dig @127.0.0.1 -p 53 PTR 1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa
```

If you want to test over IPv6 loopback:

```sh
dig @::1 -p 53 AAAA eaaq3o-e.v6.alt
dig @::1 -p 53 A fsf.org 
```

## Automatic test script

The included script checks the test vectors from the Prosody documentation.

Run it against IPv4 loopback on port 53:

```sh
./test_vectors.sh
```

Run it against a different address or port:

```sh
SERVER=::1 PORT=5354 ./test_vectors.sh
SERVER=127.0.0.1 PORT=5354 ./test_vectors.sh
```

## Tested vector set

The script checks these mappings:

- `eaaq3o-e.v6.alt` -> `2001:db8::1`
- `ai-e.v6.alt` -> `200::1`
- `aiamvog6wthgaq3cisjokoiewu.v6.alt` -> `200:cab8:deb4:ce60:4362:4492:e539:4b5`
- `a-e.v6.alt` -> `::1`
- `a-a.v6.alt` -> `::`
- `72-e.v6.alt` -> `fe80::1`
- `77777777777777777777777774.v6.alt` -> `ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff`
- `ceiqaaaaaairc-rce.v6.alt` -> `1111:0:0:1111::1111`
- `ceiq-eiraaaaaaarce.v6.alt` -> `1111:0:0:0:1111::1111`

## Recommended `/etc/resolv.conf` setup

If you want to use `rn` as your system resolver, a typical `/etc/resolv.conf` is:

```conf
nameserver 127.0.0.1
```

Optionally, if you also want IPv6 loopback listed:

```conf
nameserver 127.0.0.1
nameserver ::1
```

Usually `rn` should listen on port 53 and forward non-`.v6.alt` queries to one or more upstream DNS servers.

Example:

```sh
./rn 53 1.1.1.1 8.8.8.8
```

On many Linux systems `/etc/resolv.conf` is managed by system services such as systemd, NetworkManager, or DHCP clients, so manual edits may be overwritten. On FreeBSD it is typically user-editable, but may be overwritten by `dhclient` unless configured otherwise.

## Notes

- The test script uses `dig` and expects one IPv6 address in the answer.
- `dig +short` prints canonical IPv6 text, so the expected values in the script are written in canonical compressed form where needed.
- If you want to use this daemon from `/etc/resolv.conf`, it should usually run on port 53 and forward non-`.v6.alt` queries upstream.
- The installed service files run `rn` with `-c /etc/rn.conf`.
- Binding to port 53 usually requires root privileges.
