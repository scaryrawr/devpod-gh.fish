function _devpod_reverseforward --description 'Reverse forwarding of selfhosted LLMs'
    set -l selected_space $argv[1]
    if test -z "$selected_space"
        echo "Usage: _devpod_reverseforward <workspace-name>" >&2
        return 1
    end

    # Ensure workspace is up
    echo "[devpod-gh] Ensuring workspace is up..." >&2
    command devpod up --open-ide false $selected_space >/dev/null 2>&1

    if lsof -iTCP:1234 -sTCP:LISTEN -t &>/dev/null
        echo "[devpod-gh] Reverse forwarding lm studio..." >&2
        ssh -O forward -R 1234:localhost:1234 "$selected_space.devpod" 2>/dev/null
    end

    if lsof -iTCP:11434 -sTCP:LISTEN -t &>/dev/null
        echo "[devpod-gh] Reverse forwarding ollama..." >&2
        ssh -O forward -R 11434:localhost:11434 "$selected_space.devpod" 2>/dev/null
    end
end
