#!/usr/bin/env bash

# 1. Skip aliases and overrides when inside Distrobox
if [ -n "$DISTROBOX_ENTER_PATH" ]; then
    return
fi

export VISUAL=micro
export EDITOR=micro

# 2. CLEANUP: Remove old function definitions to prevent conflicts
unset -f grep find tmux ls ll 2>/dev/null

# --- Fastfetch Wrapper ---
function fastfetch {
    if [ $# -eq 0 ]; then
        command fastfetch \
            -l /usr/share/fastfetch/presets/origami/origami-ascii.txt \
            --logo-color-1 blue \
            -c /usr/share/fastfetch/presets/origami/origami-fastfetch.jsonc
    else
        command fastfetch "$@"
    fi
}

# --- eza Aliases ---
alias la='eza -la --icons'
alias lt='eza --tree --level=2 --icons'

function _nano_nag {
    if [ -t 2 ] && [ -z "$COMP_LINE" ]; then
        printf 'Tip: Try using "micro" for better mouse support and syntax highlighting.\n' >&2
    fi
    command nano "$@"
}
alias nano='_nano_nag'
alias vim='nvim'
alias update='topgrade'

# --- eza Functions (Override ls/ll) ---
unalias ls 2>/dev/null
ls() { command eza --icons "$@"; }

unalias ll 2>/dev/null
ll() { command eza -l --icons "$@"; }

# --- Modern Replacements ---
alias docker='podman'
alias docker-compose='podman-compose'
alias cat='bat'
alias sudo='sudo-rs '
alias su='su-rs'

# --- Initializations ---
# We check if these commands exist to avoid errors on bare systems
if command -v fzf &>/dev/null; then eval "$(fzf --bash)"; fi
if command -v starship &>/dev/null; then eval "$(starship init bash)"; fi
if command -v zoxide &>/dev/null; then eval "$(zoxide init bash --cmd cd)"; fi

# --- uutils-coreutils Aliases ---
for uu_bin in /usr/bin/uu_*; do
    [ -e "$uu_bin" ] || continue
    base_cmd=$(basename "$uu_bin")
    std_cmd="${base_cmd#uu_}"
    case "$std_cmd" in
    ls | cat | '[' | test) continue ;;
    esac
    alias "$std_cmd"="$base_cmd"
done
# --- End uutils ---

# --- SAFE NAGS (Completion Aware) ---

# Helper: Checks if we are in an interactive terminal AND NOT inside an autocomplete script
function _should_nag {
    # -t 2 checks if stderr is a screen (interactive)
    # -z "$COMP_LINE" ensures we are NOT currently pressing Tab (autocomplete)
    [ -t 2 ] && [ -z "$COMP_LINE" ]
}

# 1. TMUX -> ZELLIJ
function _tmux_nag {
    if _should_nag; then
        printf 'Tip: Try using "zellij" for a modern multiplexing experience.\n' >&2
    fi
    command byobu "$@"
}
alias tmux='_tmux_nag'

# 2. FIND -> FD
function _find_nag {
    if _should_nag; then
        printf 'Tip: Try using "fd" next time for a simpler and faster search.\n' >&2
    fi
    command find "$@"
}
alias find='_find_nag'

# 3. GREP -> RG
function _grep_nag {
    if _should_nag; then
        printf 'Tip: Try using "rg" for a simpler and faster search.\n' >&2
    fi
    command grep "$@"
}
alias grep='_grep_nag'
