# devpod-gh.fish

Quality of life plugin for Fish shell.

I like vibe coding and `yolo` mode, this is to make using local devcontainers easier and more seamless for "safer" yolo.

I get GitHub Copilot through work, so getting "automatic" sign in to me is important. I have been learning neovim (and am use to vscode), so auto port forwarding.

This is a simple function wrapper around [devpod](https://github.com/loft-sh/devpod) which checks for `devpod` and [github cli](https://cli.github.com/).

## Dependencies

- [devpod](https://github.com/loft-sh/devpod) - Development container management
- [github cli](https://cli.github.com/) - GitHub authentication and token generation
- [gum](https://github.com/charmbracelet/gum) - Interactive workspace selection
- [jq](https://jqlang.github.io/jq/) - JSON processing for port monitoring
- `ssh`/`scp` - Remote connection and file transfer
- `stdbuf` - Unbuffered output handling for port monitoring
- `python3` - Local browser service (optional; browser forwarding disabled if missing)

## Installation

### Fisher

```fish
fisher install scaryrawr/devpod-gh.fish
```

## Configuration

### SSH ControlMaster (Required for optimal performance)

Configure SSH ControlMaster in your `~/.ssh/config` for optimal port forwarding performance:

```ssh-config
Host *
  ControlMaster auto
  ControlPath ~/.ssh/cm-%C
  ControlPersist 10m
```

This enables connection multiplexing, which allows multiple SSH connections to share a single network connection. This significantly speeds up establishing new port forwards by avoiding repeated SSH handshakes and authentication.

## Features

### Automatic GitHub Token Injection

When you ssh into a devpod using `devpod ssh`:

```fish
devpod ssh
```

The wrapper injects the `GH_TOKEN` environment using `gh auth token`:

```fish
devpod ssh --set-env GH_TOKEN=(gh auth token)
```

This enables things like [github copilot cli](https://github.com/features/copilot/cli/) to just work... automagically, in devpods.

It magically enables the [github cli](https://github.com/devcontainers/features/tree/main/src/github-cli) feature.

### Automatic Port Forwarding

The plugin automatically monitors and forwards ports that are bound inside your devpod workspace. When an application starts listening on a port inside the devpod, it will be automatically forwarded to your local machine on the same port.

This uses a background port monitoring process that watches for port binding events and establishes SSH tunnels as needed. The port forwarding is cleaned up automatically when you disconnect.

### Browser Opening (BROWSER + xdg-open shim)

When connecting to a devpod, the plugin automatically:

1. Starts a local browser service on your machine
2. Reverse-forwards a Unix socket into the codespace so the devpod can reach it
3. Uploads `browser-opener.sh` and an `xdg-open` shim to the codespace
4. Sets `BROWSER` so CLI tools (e.g. `gh`, `npm open`) open URLs on your local machine

**URL routing (priority order):**
- devpod browser socket (reverse-forwarded from local machine)
- `$BROWSER` environment variable
- `code --open-url` (VS Code remote)
- `/usr/bin/xdg-open` (real binary, if available)
- Silent no-op

**xdg-open file handling:**
The `xdg-open` shim also handles local file opens with environment-aware behaviour:
- **In tmux**: opens in a vertical split pane
- **SSH without tmux**: runs viewer inline (blocking)
- **Non-SSH**: delegates to real `xdg-open` or VS Code

File-type viewers (graceful fallback):
- Images (jpg/png/gif/…) → `chafa`
- PDFs → `pdftotext` + `less`, or `pdfinfo`
- Markdown → `glow` → `bat` → `$EDITOR`
- Everything else → `$EDITOR` → `vi`

> **Requires:** `python3` on the local machine (for the browser service). If not available, browser forwarding is skipped and everything else continues to work.
