# rn

A small DNS server for `*.v6.alt` names.

It decodes the rightmost label before `.v6.alt` using the Prosody [mod_s2s_v6mesh](https://modules.prosody.im/mod_s2s_v6mesh.html) scheme and returns an `AAAA` record. For ordinary DNS names, it can forward queries to one or more upstream DNS servers.

## Build

Build with:

```sh
make
````

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

* `rn` to `/usr/sbin/rn`
* config to `/etc/rn.conf`
* systemd unit to `/etc/systemd/system/rn.service`
* OpenRC script to `/etc/init.d/rn`

## Service files

### systemd

The distribution includes `rn.service`.

Enable and start it with:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now rn.service
```

Check status:

```sh
systemctl status rn.service
```

### OpenRC

The distribution includes `rn.openrc` and installs with `make install`.
```
sudo install -m 755 rn.openrc /etc/init.d/rn
```

Install or update it as `/etc/init.d/rn` and enable it:

```sh
sudo rc-update add rn default
sudo rc-service rn start
```

Check status:

```sh
rc-service rn status
```

## Install on Gentoo

Add [norayr-overlay](https://github.com/norayr/norayr-overlay).

```
emerge --sync norayr-overlay
emerge net-dns/rn -av
/etc/init.d/rn start
```


## Otherwise manually start the server

Example:

```sh
./rn 53 1.1.1.1
```

Note, to use ports < 1024 the program needs to be started with root privileges.

Expected startup output:

```text
Listening on 127.0.0.1:53
Listening on [::1]:53
Forwarding non-.v6.alt queries to:
  1.1.1.1:53
```

Config-file example:

```sh
./rn -c
./rn -c /etc/rn.conf
./rn -c ./rn.conf
```

If `-c` is given without a file name, `rn` reads `/etc/rn.conf`.


## Manual tests

Local `v6.alt` query:

```sh
dig @127.0.0.1 -p 53 AAAA fiabbgadu-e.v6.alt
```

Forwarded ordinary DNS query:

```sh
dig @127.0.0.1 -p 53 A openai.com
```

If you want to test over IPv6 loopback:

```sh
dig @::1 -p 53 AAAA fiabbgadu-e.v6.alt
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

## Config file

`rn` can be started either with command-line arguments or with an INI-style config file.

Command-line form:

```sh
./rn 53 1.1.1.1 8.8.8.8
````

Config-file form:

```sh
./rn -c
./rn -c /etc/rn.conf
./rn -c ./rn.conf
```

If `-c` is given without a file name, `rn` reads `/etc/rn.conf`.

Example config:

```ini
[server]
port=53

[upstreams]
dns1=1.1.1.1
dns2=8.8.8.8
dns3=[2606:4700:4700::1111]:53
```

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

* The test script uses `dig` and expects one IPv6 address in the answer.
* `dig +short` prints canonical IPv6 text, so the expected values in the script are written in canonical compressed form where needed.
* If you want to use this daemon from `/etc/resolv.conf`, it should usually run on port 53 and forward non-`.v6.alt` queries upstream.
* The installed service files run `rn` with `-c /etc/rn.conf`.
* Binding to port 53 usually requires root privileges.
