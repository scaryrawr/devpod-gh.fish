function devpod --description 'DevPod wrapper with automatic GitHub token injection and port forwarding'
    # Skip our wrapper during tab completion (when __complete is called)
    if contains -- __complete $argv
        command devpod $argv
        return
    end

    # Skip gum selection if --help or -h is present, or non-interactive SSH flags
    if string match -q -- '*--help*' $argv; or string match -q -- '*-h*' $argv; or string match -q -- '*-L*' $argv; or string match -q -- '*--forward-local*' $argv; or string match -q -- '*-R*' $argv; or string match -q -- '*--forward-remote*' $argv; or string match -q -- '*-D*' $argv; or string match -q -- '*--forward-socks*' $argv; or string match -q -- '*-W*' $argv; or string match -q -- '*--forward-stdio*' $argv; or string match -q -- '*--command*' $argv
        command devpod $argv
        return
    end

    # Skip gum selection if not ssh command
    if not string match -q -- '*ssh*' $argv
        command devpod $argv
        return
    end

    set -l spaces (command devpod ls --provider docker --output json | jq -r '.[].id')

    set -l args $argv
    set -a args --set-env
    set -a args GH_TOKEN=(gh auth token)

    # Check if any space is already included in args
    set -l selected_space ""
    set -l space_found 0
    for space in $spaces
        if contains -- $space $argv
            set space_found 1
            set selected_space $space
            break
        end
    end

    # If no space found in args, prompt with gum
    if test $space_found -eq 0 -a -n "$spaces"
        set selected_space (printf '%s\n' $spaces | gum choose --header 'Please select a workspace from the list below')
        if test -n "$selected_space"
            set -a args $selected_space
        else
            return
        end
    end

    set -l pf_pgid
    set -l rf_pgid
    # Copy and start portmonitor.sh on the devpod if we have a selected_space
    if test -n "$selected_space"
        set -l _pf_log (mktemp -t devpod-portforward.$selected_space.XXXXXX.log)
        set -l _rf_log (mktemp -t devpod-reverseforward.$selected_space.XXXXXX.log)
        echo "[devpod-gh] Starting port forwarding monitor (log: $_pf_log)" >&2
        echo "[devpod-gh] Starting reverse forwarding monitor (log: $_rf_log)" >&2
        fish -c "_devpod_portforward $selected_space" >$_pf_log 2>&1 &
        set pf_pgid (ps -o pgid= -p $last_pid | string trim)
        fish -c "_devpod_reverseforward $selected_space" >$_rf_log 2>&1 &
        set rf_pgid (ps -o pgid= -p $last_pid | string trim)
    end

    command devpod $args
    test -n "$pf_pgid" && kill -- -$pf_pgid 2>/dev/null
    test -n "$rf_pgid" && kill -- -$rf_pgid 2>/dev/null
end
