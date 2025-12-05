# /etc/fish/conf.d/origami-aliases.fish

# disable Fish greeting
set fish_greeting ""

# Start in $HOME
if status is-interactive
    cd $HOME
end

# 1. Skip aliases and overrides when inside Distrobox
if set -q DISTROBOX_ENTER_PATH
    return
end

# 2. CLEANUP: Fish automatically handles function/alias redefinition, so explicit unsetting is less critical.
functions -e grep find tmux ls ll

# --- Fastfetch Wrapper ---
function fastfetch
    # Check if no arguments ($argv) are provided.
    if test (count $argv) -eq 0
        command fastfetch \
            -l /usr/share/fastfetch/presets/origami/origami-ascii.txt \
            --logo-color-1 blue \
            -c /usr/share/fastfetch/presets/origami/origami-fastfetch.jsonc
    else
        # Use 'command' to call the actual binary and pass all arguments ($argv)
        command fastfetch $argv
    end
end

# --- Origami Wrapper ---
function origami
    # Check if at least one argument is provided.
    if test (count $argv) -lt 1
        echo "Usage: origami {fold|unfold|status} <package>"
        echo "  📂 fold   -> installs a package"
        echo "  📄 unfold -> uninstalls a package"
        return 1
    end

    # Set local variable and shift arguments
    set action $argv[1]
    set -e argv[1]

    switch "$action"
        case fold
            echo "📂 Folding (installing) packages: $argv"
            # $argv contains the remaining arguments (packages)
            sudo rpm-ostree install $argv
        case unfold
            echo "📄 Unfolding (uninstalling) packages: $argv"
            sudo rpm-ostree uninstall $argv
        case status
            rpm-ostree status
        case "*"
            echo "❌ Error: Unknown action '$action'" >&2 # Use >&2 for stderr
            echo "Try: origami fold <pkg>, origami unfold <pkg>, or origami status" >&2
            return 1
    end
end

# --- eza Aliases ---
alias la 'eza -la --icons'
alias lt 'eza --tree --level=2 --icons'

alias vim nvim
alias update topgrade

# --- eza Functions (Override ls/ll) ---
function ls
    command eza --icons $argv
end

function ll
    command eza -l --icons $argv
end

# --- Modern Replacements ---
alias docker podman
alias docker-compose podman-compose
alias cat bat
alias sudo 'sudo-rs '
alias su su-rs

# --- Initializations ---
if type -q fzf
    fzf --fish | source
end
if type -q starship
    starship init fish | source
end
if type -q zoxide
    zoxide init fish | source
end

# --- uutils-coreutils Aliases ---
for uu_bin in /usr/bin/uu_*
    # Check if the file exists (test -e)
    if test -e "$uu_bin"
        set base_cmd (basename "$uu_bin")
        set std_cmd (string replace -r '^uu_' '' "$base_cmd")

        # Fish switch statement handles the skip logic
        switch "$std_cmd"
            case ls cat "[" test
                continue
            case "*"
                alias "$std_cmd" "$base_cmd"
        end
    end
end
# --- End uutils ---

# --- SAFE NAGS (Completion Aware) ---

# Helper: Checks if we are in an interactive terminal AND NOT inside an autocomplete script
function _should_nag
    # We check if $__fish_current_command is NOT the completion command.
    if status is-interactive
        if not set -q __fish_command_line_is_being_completed
            return 0 # True
        end
    end
    return 1 # False
end

# 1. TMUX -> ZELLIJ
function _tmux_nag
    if _should_nag
        echo 'Tip: Try using "zellij" for a modern multiplexing experience.' >&2
    end
    command byobu $argv
end
alias tmux _tmux_nag

# 2. FIND -> FD
function _find_nag
    if _should_nag
        echo 'Tip: Try using "fd" next time for a simpler and faster search.' >&2
    end
    command find $argv
end
alias find _find_nag

# 3. GREP -> RG
function _grep_nag
    if _should_nag
        echo 'Tip: Try using "rg" for a simpler and faster search.' >&2
    end
    command grep $argv
end
alias grep _grep_nag
