# Browser Watch

Watch a Docker-hosted Chromium session live in noVNC while a browser agent
controls it. The viewer is read-only by default. You can also
[save the session as an MP4](#record-a-session).

## Quick start

On a Linux host with Docker and the Compose plugin, open the directory that
contains [`compose.yml`](compose.yml). Run these steps as the non-root user who
should own the MP4s. The steps assume Docker is not running in rootless mode
and does not remap user IDs.

The viewer has no password. On a shared network, [bind it to loopback](#remote-access)
before starting the container.

1. Create the output directory and save your user and group IDs:

   ```sh
   install -d -m 0700 recordings
   if [ ! -e .env ]; then
     printf 'PUID=%s\nPGID=%s\n' "$(id -u)" "$(id -g)" > .env
   fi
   ```

   If you already have a `.env`, set `PUID` to the number from `id -u` and
   `PGID` to the number from `id -g`. If another user owns `recordings/`, see
   [Fix recording permissions](#fix-recording-permissions) before starting.

2. Build and start Browser Watch:

   ```sh
   docker compose up -d --build --wait
   ```

3. Open the [noVNC viewer](http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale)
   to see Chromium. If Docker runs on another machine, see [Remote access](#remote-access).

## Connect OpenCode (optional)

OpenCode V2 uses the included [`opencode.json`](opencode.json) when you run it
from this directory. The config connects Playwright MCP to
`http://127.0.0.1:8931/mcp`.

```sh
opencode mcp list
```

Once `browser-watch-playwright` connects, ask the agent to open
`https://example.com` with Playwright. You should see Chromium navigate in
noVNC. If OpenCode runs on a different machine from Docker, first open an
[SSH tunnel for MCP](#remote-access).

To use this config in another project, copy the `mcp.servers` entries to its
`opencode.json`. For all projects, merge them into your OpenCode user config
at `~/.config/opencode/opencode.json` or `opencode.jsonc`.

## Record a session

### Record on demand

```sh
docker compose exec browser-watch record start 300
```

This records for up to five minutes. Omit `300` to use the default of 30 minutes,
or set `RECORDING_DURATION_SECONDS` in `.env` to change that default.

To check whether a recording is running and see the file name:

```sh
docker compose exec browser-watch record status
```

To stop early and finalize the MP4:

```sh
docker compose exec browser-watch record stop
```

Finished videos appear in `./recordings/` with UTC timestamps in their names.
The recorder captures the display without audio, even if no viewer is open.
It stops when it reaches the time or size limit and does not delete older files.
Use `docker compose exec -T` when running recorder commands in a script.

### Record at startup

Add these settings to `.env` for one five-minute recording each time the
container starts:

```dotenv
RECORDING_AUTOSTART=on
RECORDING_DURATION_SECONDS=300
```

Apply the settings without rebuilding:

```sh
docker compose up -d --wait
```

### Fix recording permissions

Compose expects `./recordings/` to exist before startup. It does not create
or change the owner of that directory. New MP4s belong to `PUID:PGID` and
have mode `0600`.

If the directory belongs to root or an old account, stop Browser Watch and
set the directory owner to the user running these commands:

```sh
docker compose stop browser-watch
sudo install -d -o "$(id -u)" -g "$(id -g)" -m 0700 recordings
```

If you also need to access MP4s from the old account, transfer ownership of
the existing files:

```sh
sudo find recordings -maxdepth 1 -type f -name '*.mp4' \
  -exec chown -- "$(id -u):$(id -g)" {} +
```

Set `PUID` and `PGID` in `.env` to match, then start Browser Watch. Keep the
same Compose project name so startup can update the existing profile volume
for the new IDs. To verify the effective IDs:

```sh
docker compose exec --user node browser-watch id
```

## Environment variables

Set these values in `.env` next to [`compose.yml`](compose.yml):

| Variable | Default | Values and effect |
| --- | --- | --- |
| `PUID` / `PGID` | `1000` / `1000` | Numeric user and group IDs for the browser and recorder. Both must be nonzero. `PUID` must not belong to another account in the image. |
| `SCREEN_RESOLUTION` | `1600x1000` | `WIDTHxHEIGHT` in pixels (1–9999 per side), e.g. `1280x1390` or `1920x1080`. Sets the virtual screen and Chromium's initial window size. |
| `VNC_VIEW_ONLY` | `on` | `on` blocks keyboard and mouse input in noVNC; `off` lets you control the same Chromium session as the agent. |
| `CHROMIUM_SANDBOX` | `on` | `on` enables Chromium's sandbox; `off` disables it. Use `off` only for disposable tests with trusted content. |
| `RECORDING_AUTOSTART` | `off` | `on` starts one recording when Chromium is ready; `off` leaves recording manual. |
| `RECORDING_DURATION_SECONDS` | `1800` | Default duration in seconds (1–1800) for automatic and manual recordings. `record start <seconds>` overrides it for one recording. |
| `RECORDING_MAX_MIB` | `2048` | Recording directory budget in MiB (32–999999). The recorder also checks available disk space and leaves 16 MiB of headroom. |

Run `docker compose up -d --wait` to apply changes, including new user or
group IDs. Compose recreates the container if its settings change. Reconnect
the viewer and agent as needed. A settings change does not require a rebuild.

## Remote access

The viewer listens on host port `6080` on all interfaces by default. To limit
it to local and SSH access, replace `0.0.0.0:6080:6080` with
`127.0.0.1:6080:6080` in `compose.yml` and apply the change. Keep Playwright
MCP on `127.0.0.1:8931`: anyone who can reach it can control Chromium. Raw VNC
and Chromium's debug port are not published.

On the machine where you want to open the viewer, forward port `6080`:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:6080:127.0.0.1:6080 user@server
```

Replace `user@server` with your login on the Docker host. Leave SSH running and
open the [noVNC viewer](http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale).

If OpenCode runs outside the Docker host, forward port `8931` from the machine
running OpenCode:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8931:127.0.0.1:8931 user@server
```

If you run OpenCode and view noVNC on the same machine, you can use both `-L`
options in one SSH command.

## Use a packaged image

If you already have a Browser Watch image with `PUID` and `PGID` support,
complete [quick start step 1](#quick-start). Then set `BROWSER_WATCH_IMAGE` in
`.env` to the image's tag, such as `registry.example.com/browser-watch:1.0.0`.

Start it without building:

```sh
docker compose -f compose.yml -f compose.image.yml up -d --wait
```

Use those same `-f` options when reapplying settings with `up`. The
[`compose.image.yml`](compose.image.yml) override selects the packaged image
instead of building from this repository.

## Operations

```sh
docker compose ps
docker compose logs -f browser-watch
docker compose down
```

The `browser-profile` volume survives `docker compose down`.
Browser Watch uses root during initialization, then runs Chromium and the
recorder as `node` with the configured IDs. Use `--user node` for an interactive
shell. The `record` command selects the account automatically.

### Chromium sandbox troubleshooting

Chromium runs as non-root with its sandbox enabled by default. Compose uses
[`chromium-seccomp.json`](chromium-seccomp.json), the
[Moby default profile](https://github.com/moby/profiles/blob/9ee3204f0d0cfa19ca2c6a7b0fcf5a2b353954ae/seccomp/default.json)
(Apache 2.0), with `clone`, `setns`, and `unshare` allowed
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
`["ssh", "-T", "user@server", "docker", "exec", "-i", "--user", "node", "browser-watch", "browser-use", "--cli-mcp"]`.
SSH must work without an interactive prompt and the server account must have
Docker access. The viewer still uses `6080`.

The image sets `BU_CDP_URL=http://127.0.0.1:9222` **inside the container** and
leaves `BU_CDP_WS` empty. You do not need to set either variable on the host.
A nonempty `BU_CDP_WS` inside the container overrides `BU_CDP_URL`. To try the
Browser Use CLI from the Docker host:

```sh
printf '%s\n' 'print(list_tabs())' | docker exec -i --user node browser-watch browser-use
```

This setup does not use Browser Use Cloud.
