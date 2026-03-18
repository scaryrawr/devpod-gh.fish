function devpod --description 'DevPod wrapper with automatic GitHub token injection and port forwarding'
    # Skip our wrapper during tab completion (when __complete is called)
    if contains -- __complete $argv
        command devpod $argv
        return
    end

    # Skip interactive selection if --help or -h is present, or non-interactive SSH flags
    if string match -q -- '*--help*' $argv; or string match -q -- '*-h*' $argv; or string match -q -- '*-L*' $argv; or string match -q -- '*--forward-local*' $argv; or string match -q -- '*-R*' $argv; or string match -q -- '*--forward-remote*' $argv; or string match -q -- '*-D*' $argv; or string match -q -- '*--forward-socks*' $argv; or string match -q -- '*-W*' $argv; or string match -q -- '*--forward-stdio*' $argv; or string match -q -- '*--command*' $argv
        command devpod $argv
        return
    end

    # Skip interactive selection if not ssh command
    if not string match -q -- '*ssh*' $argv
        command devpod $argv
        return
    end

    set -l spaces (command devpod ls --provider docker --output json | jq -r '.[].id')

    set -l args $argv
    set -a args --set-env
    set -a args GH_TOKEN=(gh auth token)

    set -l config_home (test -n "$XDG_CONFIG_HOME"; and echo "$XDG_CONFIG_HOME"; or echo "$HOME/.config")
    if test -f "$config_home/github-copilot/apps.json"
        set -l copilot_token (jq -r '."github.com:Iv1.b507a08c87ecfe98".oauth_token // empty' "$config_home/github-copilot/apps.json")
        if test -n "$copilot_token"
            set -a args --set-env
            set -a args GH_COPILOT_TOKEN=$copilot_token
        end
    end

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

    # If no space found in args, prompt with gum or fzf
    if test $space_found -eq 0 -a -n "$spaces"
        if type -q gum
            set selected_space (printf '%s\n' $spaces | gum choose --header 'Please select a workspace from the list below')
        else if type -q fzf
            set selected_space (printf '%s\n' $spaces | fzf --header 'Please select a workspace from the list below')
        else
            echo "[devpod-gh] Error: neither gum nor fzf is installed. Please install one to enable workspace selection." >&2
            return 1
        end
        if test -n "$selected_space"
            set -a args $selected_space
        else
            return
        end
    end

    set -l pf_pgid
    set -l rf_pgid
    set -l browser_pid
    set -l browser_socket
    set -l func_dir (dirname (status --current-filename))
    set -l devpod_host "$selected_space.devpod"

    # Copy and start portmonitor.sh on the devpod if we have a selected_space
    if test -n "$selected_space"
        set -l _pf_log (mktemp -t devpod-portforward.$selected_space.XXXXXX.log)
        set -l _rf_log (mktemp -t devpod-reverseforward.$selected_space.XXXXXX.log)
        # Create control master if it doesn't exist, otherwise reuse existing
        if not ssh -O check "$devpod_host" 2>/dev/null
            ssh -MNf "$devpod_host"
        else
            echo "[devpod-gh] Reusing existing control connection" >&2
        end

        # Start local browser service and reverse-forward into the codespace
        if type -q python3
            set -l _port_file (mktemp -t devpod-browser-port.XXXXXX)
            python3 "$func_dir/browser-service.py" >"$_port_file" 2>/dev/null &
            set browser_pid $last_pid

            set -l browser_port ""
            for _i in (seq 10)
                set browser_port (string trim (cat "$_port_file" 2>/dev/null))
                test -n "$browser_port" && break
                sleep 0.5
            end
            rm -f "$_port_file"

            if test -n "$browser_port"
                set browser_socket "/tmp/devpod-browser-"(random)".sock"
                # Upload browser scripts and set up xdg-open symlink
                scp -q "$func_dir/browser-opener.sh" "$func_dir/xdg-open.sh" "$devpod_host:~/" 2>/dev/null
                ssh "$devpod_host" 'chmod +x ~/browser-opener.sh ~/xdg-open.sh; sudo ln -sf ~/xdg-open.sh /usr/local/bin/xdg-open 2>/dev/null; sudo ln -sf ~/browser-opener.sh /usr/local/bin/browser-opener 2>/dev/null; for s in /tmp/devpod-browser-*.sock; do [ -S "$s" ] || continue; curl -s --max-time 1 --unix-socket "$s" "http://localhost/" >/dev/null 2>&1 || rm -f "$s"; done; true' 2>/dev/null
                # Reverse-forward Unix socket into the codespace
                ssh -O forward -R "$browser_socket:localhost:$browser_port" "$devpod_host" 2>/dev/null
                if test $status -eq 0
                    echo "[devpod-gh] Browser service started (port $browser_port → $browser_socket)" >&2
                    set -a args --set-env
                    set -a args BROWSER=/usr/local/bin/browser-opener
                else
                    echo "[devpod-gh] Warning: Failed to forward browser socket" >&2
                end
            else
                echo "[devpod-gh] Warning: Failed to start browser service" >&2
                kill $browser_pid 2>/dev/null
                set browser_pid ""
            end
        else
            echo "[devpod-gh] Warning: python3 not found, browser forwarding disabled" >&2
        end

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
    test -n "$browser_pid" && kill $browser_pid 2>/dev/null
    if test -n "$browser_socket"
        ssh -O cancel -R "$browser_socket" "$devpod_host" 2>/dev/null
    end

    # Keep control connection alive for reuse (ControlPersist handles cleanup)
end
