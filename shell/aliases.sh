# ~/dots/shell/aliases.sh — aliases for engagement work

# --- Navigation / listing ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
command -v eza >/dev/null && alias ll='eza -lah --group-directories-first' || alias ll='ls -lah'
command -v bat  >/dev/null && alias cat='bat --paging=never' 2>/dev/null
command -v batcat >/dev/null && alias bat='batcat'

# --- Clipboard (WSL: use Windows clip.exe; fall back to xclip) ---
if command -v clip.exe >/dev/null; then
    alias clip='clip.exe'
elif command -v xclip >/dev/null; then
    alias clip='xclip -selection clipboard'
fi

# --- Networking / recon shortcuts ---
alias ports='ss -tulpn'                       # local listeners
alias myip='ip -4 -o addr show | awk "{print \$2, \$4}" | grep -v "^lo "'
alias listening='ss -tlpn'
alias serve-here='python3 -m http.server'      # quick HTTP server (see `serve` fn for LHOST url)

# --- Tooling shortcuts ---
alias nx='nxc'                                 # netexec
alias msf='msfconsole -q'
alias vpnip='ip -4 -o addr show tun0 2>/dev/null | awk "{print \$4}" | cut -d/ -f1'

# --- Safety / quality of life ---
alias mkdir='mkdir -pv'
alias grepr='grep -RIn --color=auto'
alias watch='watch --color'
