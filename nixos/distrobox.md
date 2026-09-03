# distrobox

Running `.deb` / `.rpm` applications on this machine, by giving them a real Ubuntu
userspace instead of trying to relink them against Nix libraries.

Enabled by `distrobox` in `environment.systemPackages` (configuration.nix). That is the
whole config change — see "Why not podman" below.

## Quick reference

```bash
distrobox create --name ubuntu --image ubuntu:24.04   # once
distrobox enter ubuntu                                # shell inside; starts it if stopped
sudo apt update && sudo apt install ~/Downloads/some.deb
distrobox enter ubuntu -- distrobox-export --app someapp   # add to host app menu
```

```bash
distrobox list                       # containers
distrobox stop ubuntu                # shut down, frees its RAM
distrobox rm ubuntu                  # delete container
docker rmi ubuntu:24.04              # then reclaim the image (~80 MB + apt packages)
```

## What is shared with the host

| Shared | Container's own |
| --- | --- |
| Kernel (NixOS) | `/usr`, `/lib`, `/etc`, glibc |
| `/home/malay` — bind mount, the **real** files | `apt` + dpkg database |
| Network, `/dev/dri` (GPU), Wayland/X socket, dbus | its own `/var`, services |
| Your UID; processes visible both ways | |

It is a container, not a VM. No separate kernel, no kernel modules. Anything the app writes
to your home directory is written to your **actual** home directory — that is the point,
but it also means a misbehaving app is not sandboxed from your files.

## Adding an app to the host menu

```bash
distrobox enter ubuntu -- distrobox-export --app chatgpt
```

`--app` takes the desktop-entry basename as it exists in the container — check with
`distrobox enter ubuntu -- ls /usr/share/applications/` first. It writes
`~/.local/share/applications/ubuntu-<name>.desktop` on the host and copies the icon to
`~/.local/share/icons/`, so rofi/wofi pick it up with no config change.

The generated `Exec=` runs `distrobox-enter`, which **starts the container if it is
stopped**. So launching from the app menu just works after a reboot; you never need to
`distrobox enter` by hand.

The entry is named `<App> (on ubuntu)`. Edit `Name=` in the host `.desktop` file to drop
the suffix — re-exporting overwrites it.

```bash
distrobox enter ubuntu -- distrobox-export --app chatgpt --delete   # undo
distrobox enter ubuntu -- distrobox-export --bin /usr/bin/tool \
  --export-path ~/.local/bin                                       # CLI instead of GUI
```

## Lifecycle

- The container **keeps running after you exit the shell** — an init process holds it open
  so exported apps attach instantly.
- Idle cost measured on this machine: **0.00% CPU, ~158 MB RAM**.
- Restart policy is `no`, so it does **not** come back automatically after a reboot.
  `distrobox enter` or an exported launcher starts it again (a second or two).
- To have it survive reboots on its own: `docker update --restart unless-stopped ubuntu`.

## Why not podman

Distrobox defaults to rootless podman, and most guides recommend it, because it avoids a
root daemon and avoids needing the `docker` group — which is effectively root-equivalent on
the host.

That argument does not apply here: this machine already runs the docker daemon
(`virtualisation.docker.enable`) and `malay` is already in the `docker` group, so podman
would only add a second container runtime for no gain. Distrobox auto-detects its backend
(podman → docker → lilipod) and picks docker on its own.

If podman is ever installed for something else, distrobox will silently switch to it. Force
it back with `DBX_CONTAINER_MANAGER=docker`.

The one real difference: with rootful docker the container runs as root and distrobox
creates a matching user inside, where rootless podman maps the UID by construction. Both
give correctly-owned files in `$HOME` in practice, but ownership oddities are a known
occasional papercut on the docker backend.

## Gotchas

- **GPU / EGL warnings on first run are normal.** Container Mesa has to line up with the
  host amdgpu driver. Judge whether an app works by whether it runs, not by these warnings.
- **`apt` state is invisible to `nixos-rebuild`.** Nothing installed in the container is in
  the flake or in git. Treat the container as disposable: if it matters, write down the
  `apt install` line here, or recreate from scratch.
- **Disk is the real cost.** Ubuntu base plus an Electron app's GTK/NSS/Mesa dependency
  tree runs 1.5–3 GB, duplicating libraries that already exist in the Nix store.

## Why this instead of packaging the .deb

There was a `debinstall` tool here that unpacked `.deb`s and relinked them with
`autoPatchelfHook`. It worked — including on the ChatGPT app, which linked cleanly with
`libusb1` added and Qt routed around a setup-hook conflict — but the app then died with
`SIGILL` about four seconds after launch, a V8 fatal abort in a Node worker, triggered by
existing `~/.codex` state rather than by any missing library. The same app and the same home
directory ran fine under Ubuntu in a container.

The lesson worth keeping: relinking fixes *linking*. It cannot fix an application that
depends on the rest of a distro's userspace behaving a particular way. For a self-contained
binary, patching is cheap and stays declarative; for a complex app that shells out to system
tools and expects FHS, a container is less work and more likely to actually run.

Check `nix search nixpkgs <name>` first regardless — a packaged version beats both.
