# Browser Watch

Run Chromium in Docker, control it with a browser agent, and watch the same
session live in noVNC. The viewer is read-only by default. An optional
[recorder](#record-a-session) saves the visible session as an MP4.

## Quick start

### 1. Start Browser Watch

With Docker and the Compose plugin installed, run this from the directory
containing [`compose.yml`](compose.yml) on the Docker host:

```sh
docker compose up -d --build --wait
```

### 2. Open the live viewer

If your browser runs on the Docker host, open
[the noVNC viewer](http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale)
directly. If Docker is on a remote server, run this on the machine where you
will open the viewer, then open the same link:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:6080:127.0.0.1:6081 user@server
```

Replace `user@server` with your SSH login and leave the tunnel running. If you
only want to watch, you do not need to forward `8931`.

### 3. Connect the agent (optional)

For OpenCode V2, run OpenCode from this directory to use the included
[`opencode.json`](opencode.json). To use it in another project, merge its
`mcp.servers` entries into that project's configuration. To make them available
in all projects, merge them into `~/.config/opencode/opencode.json(c)` instead.
The included config enables **Playwright MCP** at `http://127.0.0.1:8931/mcp`.

If OpenCode runs on the Docker host, no MCP tunnel is needed. Otherwise, run
this on the machine where OpenCode runs:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8931:127.0.0.1:8931 user@server
```

Leave the tunnel running; the MCP URL stays the same. If the viewer and
OpenCode are on the same machine, you can put both `-L` options in one SSH
command.

Run `opencode mcp list` to check the connection, then ask the agent to open
`https://example.com` with Playwright and watch it navigate in noVNC.

## Record a session

On the Docker host, create a private output directory next to `compose.yml`.
The browser runs as UID and GID `1000` inside the container. If your host user
has those IDs, create the directory with `mkdir -p -m 700 recordings`.
Otherwise, or if Compose already created it as root, run
`sudo install -d -o 1000 -g 1000 -m 0700 recordings`.

Recording is manual by default. To start a five-minute recording each time
the container starts, add this to `.env` next to `compose.yml`:

```dotenv
RECORDING_AUTOSTART=on
RECORDING_DURATION_SECONDS=300
```

Run `docker compose up -d --build --wait` once to install FFmpeg and mount the
output directory. Upgrading an existing deployment recreates the container once;
keep the same Compose project name to reuse the browser profile volume. You can
then record without changing Compose or restarting Chromium:

```sh
docker compose exec browser-watch record start      # Uses RECORDING_DURATION_SECONDS
docker compose exec browser-watch record status
docker compose exec browser-watch record stop       # Finalize the MP4 early
```

To override the default duration, pass the number of seconds (1–1800), for example
`docker compose exec browser-watch record start 300`. The command returns
once FFmpeg is writing; it stops at the time or size limit, whichever comes first.
Use `docker compose exec -T` instead when scripting these commands.

The recorder checks free disk space and the `./recordings/` budget before
starting, leaving 16 MiB of headroom. The default budget is 2048 MiB; override it
for a recording with `docker compose exec -e RECORDING_MAX_MIB=1024 browser-watch record start`
(allowed range: 32–999999 MiB). It never deletes old videos.

FFmpeg captures Xvfb display `:99` inside `browser-watch`, so no noVNC viewer
needs to be open. Videos contain only what's visible on that display, without
audio. MP4s are saved with UTC timestamps in `./recordings/` and are not served
by noVNC or included in Git or the Docker build context. They may contain
sensitive information. If your host user cannot read the directory directly,
copy a finished video with `docker compose cp browser-watch:/recordings/<filename>.mp4 .`
(replace `<filename>` with the name reported by `record status`).

## Environment variables

Set these values in a `.env` file next to [`compose.yml`](compose.yml), or
set them directly in the service's `environment` block:

| Variable | Default | Values and effect |
| --- | --- | --- |
| `SCREEN_RESOLUTION` | `1600x1000` | `WIDTHxHEIGHT` in pixels (1–9999 per side), e.g. `1280x1390` or `1920x1080`. Sets the virtual screen and Chromium's initial window size. |
| `VNC_VIEW_ONLY` | `on` | `on` blocks keyboard and mouse input in noVNC; `off` lets you control the same Chromium session as the agent. |
| `CHROMIUM_SANDBOX` | `on` | `on` enables Chromium's sandbox; `off` disables it. Use `off` only for disposable tests with trusted content. |
| `RECORDING_AUTOSTART` | `off` | `on` starts one recording when Chromium is ready; `off` leaves recording manual. |
| `RECORDING_DURATION_SECONDS` | `1800` | Default duration in seconds (1–1800) for automatic and manual recordings. `record start <seconds>` overrides it for one recording. |
| `RECORDING_MAX_MIB` | `2048` | Total recording directory budget in MiB (32–999999). |

For example, to use a 1280×1390 screen with manual control:

```dotenv
SCREEN_RESOLUTION=1280x1390
VNC_VIEW_ONLY=off
```

Run `docker compose up -d --wait` to apply changes. Compose recreates the
container if its settings changed, so reconnect the viewer and agent as needed.
The browser profile is preserved. The viewer URL works in either mode:
`resize=scale` fits the display to your window without changing its resolution.
In interactive mode, take turns with the agent so you don't interrupt each
other.

## Ports and remote access

| Service | Container port | Published on the Docker host |
| --- | --- | --- |
| noVNC live viewer | `6080` | `127.0.0.1:6081` |
| Playwright MCP | `8931` | `127.0.0.1:8931` |
| Raw VNC | `5900` | Not published |
| Chromium DevTools (CDP) | `9222` | Not published |

The Playwright MCP port is **`8931`, not `8391`**. Playwright listens on
`0.0.0.0:8931` **inside the container** so Docker can forward traffic to it.
The Compose mapping `127.0.0.1:8931:8931` binds the host port to loopback only:
the first `8931` is the host port, and the second is the container port.
`EXPOSE` in the [`Dockerfile`](Dockerfile) documents the container ports;
it does not publish them.

Keep both ports bound to loopback. The viewer has no password, and the MCP
endpoint can control the active browser session. Use the SSH tunnels in
[Quick start](#quick-start) instead of publishing either service on a network
interface. On the Docker host, run `docker compose port browser-watch 8931`
to check the MCP binding while the service is running.

## Operations

```sh
docker compose ps
docker compose logs -f browser-watch
docker compose down
```

The `browser-profile` volume survives `docker compose down`.

### Chromium sandbox troubleshooting

Chromium runs as non-root with its sandbox enabled by default. Compose uses
[`chromium-seccomp.json`](chromium-seccomp.json), the
[Moby default profile](https://github.com/moby/profiles/blob/9ee3204f0d0cfa19ca2c6a7b0fcf5a2b353954ae/seccomp/default.json)
([Apache 2.0](LICENSE-moby.txt)), with `clone`, `setns` and `unshare` allowed
for Chromium's user namespaces. This does not change Docker's global settings.
If Chromium reports a sandbox error, check the host's user-namespace policy
first.

## Alternative: Browser Use MCP

Browser Use can control the same Chromium session without the Playwright port.
In [`opencode.json`](opencode.json), remove `"disabled": true` from
`browser-watch-browser-use` and set `"disabled": true` on
`browser-watch-playwright`. Use one MCP at a time to avoid conflicting actions.

The Browser Use command uses `docker exec -i` on the Docker host. If OpenCode
runs elsewhere, replace its `command` array with
`["ssh", "-T", "user@server", "docker", "exec", "-i", "browser-watch", "browser-use", "--cli-mcp"]`.
SSH must work without an interactive prompt and the server account must have
Docker access. The viewer still uses `6081`.

The image sets `BU_CDP_URL=http://127.0.0.1:9222` **inside the container** and
leaves `BU_CDP_WS` empty. You do not need to set either variable on the host.
A nonempty `BU_CDP_WS` inside the container overrides `BU_CDP_URL`. To try the
Browser Use CLI from the Docker host:

```sh
printf '%s\n' 'print(list_tabs())' | docker exec -i browser-watch browser-use
```

This setup does not use Browser Use Cloud.
