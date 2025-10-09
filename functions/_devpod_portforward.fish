function _devpod_portforward --description 'Manage automatic port forwarding for a devpod workspace'
    set -l selected_space $argv[1]
    if test -z "$selected_space"
        echo "Usage: _devpod_portforward <workspace-name>" >&2
        return 1
    end

    # Sanitize workspace name for use in variable names (replace invalid chars with underscores)
    set -l safe_space (string replace -ra '[^a-zA-Z0-9_]' '_' -- $selected_space)

    # Ensure workspace is up
    echo "[devpod-gh] Ensuring workspace is up..." >&2
    command devpod up --open-ide false $selected_space >/dev/null 2>&1

    # Copy monitoring script
    set -l script_path (dirname (status --current-filename))/../portmonitor.sh
    set -l devpod_host "$selected_space.devpod"
    echo "[devpod-gh] Copying portmonitor script..." >&2
    scp -q $script_path $devpod_host:~/ 2>/dev/null

    # Initialize associative array for port forward PIDs (using global variable)
    set -g DEVPOD_PORT_FORWARD_PIDS_$safe_space

    # Cleanup function
    function cleanup_port_forwarding_$safe_space --on-signal SIGINT --on-signal SIGTERM --on-event fish_exit
        set -l var_name DEVPOD_PORT_FORWARD_PIDS_$safe_space
        for pid in $$var_name
            kill $pid 2>/dev/null
        end
    end

    echo "[devpod-gh] Port monitoring started for workspace: $selected_space" >&2
    echo "[devpod-gh] Starting SSH monitoring loop..." >&2

    # Start SSH monitoring loop
    # The loop will exit naturally when the SSH connection closes
    command devpod ssh --command 'exec stdbuf -oL bash ~/portmonitor.sh' $selected_space </dev/null 2>&1 | while read -l line
        echo "[devpod-gh] Received: $line" >&2
        set -l event_type (echo $line | jq -r '.type // empty')
        if test "$event_type" = port
            set -l action (echo $line | jq -r '.action // empty')
            set -l port (echo $line | jq -r '.port // empty')
            if test "$action" = bound -a -n "$port"
                command devpod ssh -L $port $selected_space </dev/null >/dev/null 2>&1 &
                set -l forward_pid (jobs -l -p | tail -n1)
                disown $forward_pid
                set -l var_name DEVPOD_PORT_FORWARD_PIDS_$safe_space
                set -a $var_name $forward_pid
                echo "[devpod-gh] Port forwarding started: $port (PID: $forward_pid)" >&2
            else if test "$action" = unbound -a -n "$port"
                set -l var_name DEVPOD_PORT_FORWARD_PIDS_$safe_space
                for pid in $$var_name
                    kill $pid 2>/dev/null
                end
                echo "[devpod-gh] Port forwarding stopped: $port" >&2
            end
        end
    end

    # Cleanup when monitoring exits (workspace stopped or SSH connection closed)
    echo "[devpod-gh] SSH monitoring ended, cleaning up port forwards..." >&2
    set -l var_name DEVPOD_PORT_FORWARD_PIDS_$safe_space
    for pid in $$var_name
        kill $pid 2>/dev/null
    end
    set -e $var_name
    functions -e cleanup_port_forwarding_$safe_space
    echo "[devpod-gh] Port forwarding cleanup complete for: $selected_space" >&2
end
