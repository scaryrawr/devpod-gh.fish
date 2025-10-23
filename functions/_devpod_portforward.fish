function _devpod_portforward --description 'Manage automatic port forwarding for a devpod workspace'
    set -l selected_space $argv[1]
    if test -z "$selected_space"
        echo "Usage: _devpod_portforward <workspace-name>" >&2
        return 1
    end

    # Ensure workspace is up
    echo "[devpod-gh] Ensuring workspace is up..." >&2
    command devpod up --open-ide false $selected_space >/dev/null 2>&1

    # Copy monitoring script
    set -l script_path (dirname (status --current-filename))/portmonitor.sh
    set -l devpod_host "$selected_space.devpod"
    echo "[devpod-gh] Copying portmonitor script..." >&2
    scp -q $script_path $devpod_host:~/ 2>/dev/null

    echo "[devpod-gh] Port monitoring started for workspace: $selected_space" >&2
    echo "[devpod-gh] Starting SSH monitoring loop..." >&2

    # Start SSH monitoring loop
    ssh "$selected_space.devpod" 'exec stdbuf -oL bash ~/portmonitor.sh' </dev/null 2>&1 | while read -l line
        echo "[devpod-gh] Received: $line" >&2
        set -l event_type (echo $line | jq -r '.type // empty')
        if test "$event_type" = port
            set -l action (echo $line | jq -r '.action // empty')
            set -l port (echo $line | jq -r '.port // empty')
            if test "$action" = bound -a -n "$port"
                ssh -O forward -L $port:localhost:$port "$selected_space.devpod" 2>/dev/null
                echo "[devpod-gh] Port forwarding started: $port" >&2
            else if test "$action" = unbound -a -n "$port"
                ssh -O cancel -L $port:localhost:$port "$selected_space.devpod" 2>/dev/null
                echo "[devpod-gh] Port forwarding stopped: $port" >&2
            end
        end
    end
end
