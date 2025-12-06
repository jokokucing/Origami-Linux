#!/usr/bin/env fish

# ============================================================================ #
# Origami shell convenience layer
# ============================================================================ #

# --- Fish Shell --------------------------------------------------------------

# Disable welcome message
set fish_greeting ""

# Start in home path
if status is-interactive
    cd $HOME
end

# --- Environment guard -------------------------------------------------------
if set -q DISTROBOX_ENTER_PATH
    return
end

# --- Cleanup -----------------------------------------------------------------
functions -e grep find tmux ls ll nano git ps du

# --- Helper utilities --------------------------------------------------------
function _command_exists
    command -v "$argv[1]" >/dev/null 2>&1
end

function _eval_if_available
    set binary "$argv[1]"
    set -e argv[1]
    if _command_exists "$binary"
        eval ("$binary" "$argv")
    end
end

function _should_nag
    # Check if the shell is interactive and not in the middle of a completion
    if status is-interactive
        if not set -q __fish_command_line_is_being_completed
            if not string match -q -- "--help" $argv
                return 0 # True
            end
        end
    end
    return 1 # False
end

function _nag_and_exec
    set tip "$argv[1]"
    set -e argv[1]
    set target "$argv[1]"
    set -e argv[1]
    if _should_nag
        printf '%s\n' "$tip" >&2
    end
    # Expand $argv as separate arguments (don't quote) so the target command receives them correctly
    command "$target" $argv
end

# --- Wrappers ----------------------------------------------------------------
function fastfetch
    if test (count $argv) -eq 0
        command fastfetch \
            -l /usr/share/fastfetch/presets/origami/origami-ascii.txt \
            --logo-color-1 blue \
            -c /usr/share/fastfetch/presets/origami/origami-fastfetch.jsonc
    else
        command fastfetch $argv
    end
end

# --- Modern replacements -----------------------------------------------------
alias vim 'nvim'
alias update 'topgrade'
alias docker 'podman'
alias docker-compose 'podman-compose'
alias cat 'bat'
alias sudo 'sudo-rs '
alias su 'su-rs'

# --- Directory listings via eza ----------------------------------------------
alias la 'eza -la --icons'
alias lt 'eza --tree --level=2 --icons'
function ls
    command eza --icons $argv
end
function ll
    command eza -l --icons $argv
end

# --- Interactive tooling -----------------------------------------------------
if type -q fzf
    fzf --fish | source
end
    if type -q starship
        starship init fish | source
    end
if type -q zoxide
    zoxide init fish | source
end

# --- uutils-coreutils shims --------------------------------------------------
function _register_uutils_aliases
    for uu_bin in /usr/bin/uu_*
        if test -e "$uu_bin"
            set base_cmd (basename "$uu_bin")
            set std_cmd (string replace -r '^uu_' '' "$base_cmd")
            switch "$std_cmd"
                case ls cat '[' test
                    continue
            end
            alias "$std_cmd" "$base_cmd"
        end
    end
end
_register_uutils_aliases

# --- Friendly migration nags -------------------------------------------------
function tmux
    # Forward all arguments to _nag_and_exec which will print the tip (when appropriate)
    # and then execute the real `tmux` command with the same arguments.
    _nag_and_exec '🌀 Tip: Try using "zellij or byobu" for a modern multiplexing experience.' tmux $argv
end

function _find_nag
    _nag_and_exec '🧭 Tip: Try using "fd" next time for a simpler and faster search.' find $argv
end
alias find '_find_nag'

function _grep_nag
    _nag_and_exec '🔍 Tip: Try using "rg" for a simpler and faster search.' grep $argv
end
alias grep '_grep_nag'

function _nano_nag
    _nag_and_exec '📝 Tip: Give "micro" a try for a friendlier terminal editor.' nano $argv
end
alias nano '_nano_nag'

function _git_nag
    _nag_and_exec '🐙 Tip: Try "lazygit" for a slick TUI when working with git.' git $argv
end
alias git '_git_nag'

function _ps_nag
    _nag_and_exec '🧾 Tip: "procs" offers a richer, colorful process viewer than ps.' ps $argv
end
alias ps '_ps_nag'

function _du_nag
    _nag_and_exec '🌬️ Tip: "dust" makes disk usage checks faster and easier than du.' du $argv
end
alias du '_du_nag'
