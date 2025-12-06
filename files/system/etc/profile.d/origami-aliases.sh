#!/usr/bin/env bash

# ============================================================================ #
# Origami shell convenience layer
# ============================================================================ #

# --- Environment guard -------------------------------------------------------
if [ -n "$DISTROBOX_ENTER_PATH" ]; then
    return
fi

# --- Cleanup -----------------------------------------------------------------
unset -f grep find tmux ls ll nano git ps du 2>/dev/null
unalias ls 2>/dev/null
unalias ll 2>/dev/null

# --- Helper utilities --------------------------------------------------------
_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

_eval_if_available() {
    local binary="$1"
    shift
    if _command_exists "$binary"; then
        eval "$("$binary" "$@")"
    fi
}

_should_nag() {
    [ -t 2 ] && [ -z "$COMP_LINE" ]
}

_nag_and_exec() {
    local tip="$1"
    shift
    local target="$1"
    shift
    if _should_nag; then
        printf '%s\n' "$tip" >&2
    fi
    command "$target" "$@"
}

# --- Wrappers ----------------------------------------------------------------
fastfetch() {
    if [ $# -eq 0 ]; then
        command fastfetch \
            -l /usr/share/fastfetch/presets/origami/origami-ascii.txt \
            --logo-color-1 blue \
            -c /usr/share/fastfetch/presets/origami/origami-fastfetch.jsonc
    else
        command fastfetch "$@"
    fi
}

# --- Modern replacements -----------------------------------------------------
alias vim='nvim'
alias update='topgrade'
alias docker='podman'
alias docker-compose='podman-compose'
alias cat='bat'
alias sudo='sudo-rs '
alias su='su-rs'

# --- Directory listings via eza ----------------------------------------------
alias la='eza -la --icons'
alias lt='eza --tree --level=2 --icons'
ls() { command eza --icons "$@"; }
ll() { command eza -l --icons "$@"; }

# --- Interactive tooling -----------------------------------------------------
_eval_if_available fzf --bash
_eval_if_available starship init bash
_eval_if_available zoxide init bash --cmd cd

# --- uutils-coreutils shims --------------------------------------------------
_register_uutils_aliases() {
    local uu_bin base_cmd std_cmd
    for uu_bin in /usr/bin/uu_*; do
        [ -e "$uu_bin" ] || continue
        base_cmd=$(basename "$uu_bin")
        std_cmd="${base_cmd#uu_}"
        case "$std_cmd" in
        ls | cat | '[' | test) continue ;;
        esac
        alias "$std_cmd"="$base_cmd"
    done
}
_register_uutils_aliases

# --- Friendly migration nags -------------------------------------------------
_tmux_nag() {
    _nag_and_exec '🌀 Tip: Try using "zellij or byobu" for a modern multiplexing experience.' tmux "$@"
}
alias tmux='_tmux_nag'

_find_nag() {
    _nag_and_exec '🧭 Tip: Try using "fd" next time for a simpler and faster search.' find "$@"
}
alias find='_find_nag'

_grep_nag() {
    _nag_and_exec '🔍 Tip: Try using "rg" for a simpler and faster search.' grep "$@"
}
alias grep='_grep_nag'

_nano_nag() {
    _nag_and_exec '📝 Tip: Give "micro" a try for a friendlier terminal editor.' nano "$@"
}
alias nano='_nano_nag'

_git_nag() {
    _nag_and_exec '🐙 Tip: Try "lazygit" for a slick TUI when working with git.' git "$@"
}
alias git='_git_nag'

_ps_nag() {
    _nag_and_exec '🧾 Tip: "procs" offers a richer, colorful process viewer than ps.' ps "$@"
}
alias ps='_ps_nag'

_du_nag() {
    _nag_and_exec '🌬️ Tip: "dust" makes disk usage checks faster and easier than du.' du "$@"
}
alias du='_du_nag'
