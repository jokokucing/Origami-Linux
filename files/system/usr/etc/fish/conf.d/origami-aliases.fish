#!/usr/bin/env fish

# ============================================================================ #
# Origami shell convenience layer
# ============================================================================ #

# --- Fish Shell --------------------------------------------------------------

# --- Environment guard -------------------------------------------------------
if set -q DISTROBOX_ENTER_PATH
    return
end

# Disable welcome message
set -g fish_greeting ""

# Start in home path
if status is-interactive
    # cd $HOME

    # --- Modern replacements -----------------------------------------------------
    alias vim nvim
    alias htop btop
    alias update topgrade
    alias docker podman
    alias docker-compose podman-compose
    alias cat bat
    alias sudo 'sudo-rs '
    alias su su-rs

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
    fzf --fish | source
    zoxide init fish | source
    starship init fish | source

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
        set -l output ("$binary" "$argv" 2>&1)
        if test $status -eq 0
            eval $output
        end
    end
end

function _should_nag
    # Only "nag" in a real, interactive terminal run of the command
    #
    # - status is-interactive: we're in an interactive shell
    # - test -t 1: stdout is a TTY (completions run the command with
    #   stdout/stderr redirected to pipes, so this will be false there)
    # - skip when user explicitly asks for --help
    if status is-interactive
        if test -t 1
            if not string match -q -- --help $argv
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
        set -l config_dir /usr/share/fastfetch/presets/origami
        if test -f "$config_dir/origami-ascii.txt" -a -f "$config_dir/origami-fastfetch.jsonc"
            command fastfetch \
                -l "$config_dir/origami-ascii.txt" \
                --logo-color-1 blue \
                -c "$config_dir/origami-fastfetch.jsonc"
        else
            command fastfetch
        end
    else
        command fastfetch $argv
    end
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
function _tmux_nag
    _nag_and_exec '🌀 Tip: Try using "zellij or byobu" for a modern multiplexing experience.' tmux $argv
end
alias tmux _tmux_nag

function _find_nag
    _nag_and_exec '🧭 Tip: Try using "fd" next time for a simpler and faster search.' find $argv
end
alias find _find_nag

function _grep_nag
    _nag_and_exec '🔍 Tip: Try using "rg" for a simpler and faster search.' grep $argv
end
alias grep _grep_nag

function _nano_nag
    _nag_and_exec '📝 Tip: Give "micro" a try for a friendlier terminal editor.' nano $argv
end
alias nano _nano_nag

function _git_nag
    _nag_and_exec '🐙 Tip: Try "lazygit" for a slick TUI when working with git.' git $argv
end
alias git _git_nag

function _ps_nag
    _nag_and_exec '🧾 Tip: "procs" offers a richer, colorful process viewer than ps.' ps $argv
end
alias ps _ps_nag

function _du_nag
    _nag_and_exec '🌬️ Tip: "dust" makes disk usage checks faster and easier than du.' du $argv
end
alias du _du_nag

function _vim_nag
    _nag_and_exec '📝 Tip: Try using Helix with "hx" for a modern terminal editor.' vim $argv
end
alias vim _vim_nag

function _nvim_nag
    _nag_and_exec '📝 Tip: Try using Helix with "hx" for a modern terminal editor.' nvim $argv
end
alias nvim _nvim_nag
