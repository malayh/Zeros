# debinstall

Imperative `.deb` / `.rpm` installs on NixOS, in the spirit of `nix profile install`.

```
debinstall some_file.deb          # or: debinstall install some_file.rpm
debinstall remove <name>
debinstall list
debinstall <file> --ignore-missing
```

It unpacks the archive, relinks every binary against Nix store libraries, and adds
the result to your Nix profile. Nothing is written outside the store and the profile,
so `debinstall remove` is a complete uninstall.

## Files

| File | Role |
| --- | --- |
| `default.nix` | The `debinstall` CLI. A `writeShellApplication`; parses args, reads `pname`/`version` from the package metadata, calls `nix build` on `generic.nix`, then `nix profile add`. |
| `generic.nix` | The derivation that does the actual work. Takes `nixpkgs`, `srcPath`, `pname`, `version`, `format`, `ignoreMissing` as `--argstr` strings. |

Wired into `nixos/home.nix` as `(callPackage ./pkgs/debinstall { })`.

`default.nix` bakes `${path}` (= `pkgs.path`) into the script, so builds always use the
flake-pinned nixpkgs. No channels, no `<nixpkgs>`, no registry entry required.

## How a package is built

`generic.nix` runs these stages:

1. **Unpack** — `dpkg-deb -x` or `rpmextract` into `unpacked/`.
2. **Relocate** — `usr/` merges into `$out/`; `opt srv etc lib var` are copied to
   `$out/<dir>`. `usr/local/` is flattened into `$out/`.
3. **Fix symlinks** — absolute links pointing at `/usr/...`, `/opt/...`, `/etc/...`,
   `/srv/...` are rewritten to the corresponding `$out` path. Vendor debs ship these
   constantly (`/usr/bin/foo -> /opt/foo/foo`), and they are dangling otherwise.
4. **Fix desktop files** — `s|/usr/|$out/|` and `s|/opt/|$out/opt/|` over
   `share/applications/*.desktop`, so `Exec=` and `Icon=` resolve.
5. **Promote `/opt` binaries** — executables under `$out/opt/*/bin/` or named after the
   package get symlinked into `$out/bin`.
6. **autoPatchelfHook** — rewrites each ELF's interpreter and RPATH to the store, using
   `buildInputs` plus anything registered by `preFixup` via `addAutoPatchelfSearchPath`.
   This is the step that makes a foreign binary run.
7. **Wrap** — every `$out/bin/*` gets `--prefix LD_LIBRARY_PATH` with `runtimeLibs`.
   Step 6 cannot see `dlopen()`ed libraries; this catches them.

`dontStrip = true` — stripping vendor binaries breaks Electron and anything signed.

## Adding a library

The single most common change. A build fails with:

```
auto-patchelf: could not satisfy dependency libfoo.so.1 wanted by /nix/store/...
```

Find the provider, then add it to the `runtimeLibs` list in `generic.nix`:

```bash
nix-locate -1 libfoo.so.1        # needs nix-index; nix run nixpkgs#nix-index first
```

### How the lists are written

Every entry is a **list of candidate attribute names as strings**, resolved by
`resolveFirst`: the first name that exists in the current nixpkgs wins, and an entry where
none exist is dropped. Nested paths (`xorg.libX11`, `stdenv.cc.cc.lib`) work.

```nix
[ "libgbm" "mesa" ]                 # new name first, old name as fallback
[ "libx11" "xorg.libX11" ]
```

This is not decoration. nixpkgs renames library attributes regularly — 26.05 flattened the
whole `xorg` set — and the old paths survive as aliases that print a deprecation warning on
every single build. Putting the current name first means the alias is never evaluated, so
no warning; keeping the old name second means the file still evaluates on an older nixpkgs
instead of breaking your entire system config. **When you see a deprecation warning during
a build, fix it by prepending the new name, not by replacing the old one.**

### Which list to add to

| List | Effect | Use when |
| --- | --- | --- |
| `runtimeLibs` | `buildInputs` (step 6) **and** `LD_LIBRARY_PATH` (step 7) | Normal case |
| `searchOnlyLibs` | autopatchelf search path only, via `preFixup` | The library's setup hook misbehaves, or you do not want it on every wrapped binary's `LD_LIBRARY_PATH` |

Qt lives in `searchOnlyLibs` for a concrete reason: `qtbase`'s setup hook aborts the build
with `Error: detected mismatched Qt dependencies` if Qt5 and Qt6 are both in `buildInputs`,
and Electron apps ship `libqt5_shim.so` *and* `libqt6_shim.so`. Routing them through
`addAutoPatchelfSearchPath` resolves both shims without either hook running.

## Iterating without a rebuild

Build the CLI straight from the source tree and run it from the store path:

```bash
cd /home/malay/Zeros/nixos
nix build --impure --no-link --print-out-paths --expr '
  let flake = builtins.getFlake "path:/home/malay/Zeros/nixos";
      pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.callPackage ./pkgs/debinstall { }'
```

Check the system config still evaluates before rebuilding:

```bash
nix eval --impure --raw "path:/home/malay/Zeros/nixos#nixosConfigurations.g14.config.system.build.toplevel.drvPath"
```

To inspect what a package actually contains:

```bash
nix shell nixpkgs#dpkg -c dpkg -x file.deb ./out && find ./out -type f -perm -111
```

## Limitations

**Maintainer scripts never run.** `preinst`/`postinst`/`prerm`/`postrm` are ignored
outright. Everything below follows from that:

- **No systemd services.** Units land inertly in `$out/lib/systemd`. To actually run one,
  translate it into a `systemd.services.<name>` block in the NixOS config.
- **No system users or groups.** Add them declaratively (`users.users.<name>`).
- **No kernel modules / DKMS.** Needs a real `boot.extraModulePackages` derivation.
- **No setuid binaries.** The store cannot hold setuid bits; use
  `security.wrappers.<name>` pointing at the store path.
- **No `/etc` config.** Files go to `$out/etc` and are not read from there. Copy what you
  need into the NixOS config.
- **No dependency resolution.** `Depends:` is ignored. Missing libraries surface as
  autopatchelf errors, which you fix by editing `runtimeLibs`.
- **No triggers.** Icon caches, mime databases, `ldconfig`, font caches — none of it runs.
  A GTK app with a missing icon usually wants `gtk-update-icon-cache` behaviour that
  simply is not happening.
- **Not declarative.** Profile installs are invisible to `nixos-rebuild` and are not in
  git. Anything you want to survive a reinstall belongs in the flake instead — see
  "Promoting to a real package".

`--ignore-missing` sets `autoPatchelfIgnoreMissingDeps` to `true`, downgrading every
unresolved library from a build failure to a warning. Useful when the missing library is
only needed by a code path you do not use. The binary will still fail at runtime if it is.

`libc.musl-x86_64.so.1` is ignored by default. Node-based apps ship both glibc and musl
builds of each native module (`foo.node` and `foo.musl.node`); the musl copies are for
Alpine and are never loaded on NixOS, but autopatchelf tries to resolve them anyway and
fails the build. Ignoring the soname is correct, not a workaround. Add further entries to
that list in `generic.nix` only when you can say the same about them.

### Verifying a build actually linked

Exit code 0 is not proof. Walk every ELF and look for unresolved names:

```bash
out=/nix/store/...-<pname>-<version>
find "$out" -type f \( -name '*.so*' -o -name '*.node' -o -perm -111 \) | while read -r f; do
  head -c4 "$f" | grep -q ELF || continue
  ldd "$f" 2>/dev/null | grep "not found" | sed "s|^|$(basename "$f"): |"
done | sort -u
```

Anything listed other than the deliberately-ignored musl entries is a real gap.

## Verified working

- `ripgrep_14.1.1-1_amd64.deb` — plain `/usr/bin` binary.
- `chatgpt_amd64.deb` — Electron, `/usr/lib/chatgpt`, Qt5+Qt6 shims, native Node modules.
  Needed `libusb1` added to `runtimeLibs`, Qt added to `searchOnlyLibs`, and the musl
  ignore. `chatgpt --version` works; the `.desktop` entry resolves through the profile.

## When to use something else

| Situation | Better tool |
| --- | --- |
| Package exists in nixpkgs | `nix profile install nixpkgs#foo` — always check first |
| Needs services, users, `/etc`, drivers | distrobox / podman container |
| Run once, no install | extract, then `nix run nixpkgs#steam-run ./usr/bin/foo` |
| GUI app on flathub | `flatpak install` — already enabled in `configuration.nix` |
| Vendored AppImage | `programs.appimage` — already enabled |

## Promoting to a real package

Once a `.deb` is proven to work under `debinstall`, converting it to a tracked package is
mostly copy-paste: make `nixos/pkgs/<name>/default.nix` a `stdenv.mkDerivation` with
`fetchurl` for `src`, the same `dpkg` + `autoPatchelfHook` `nativeBuildInputs`, and only
the libraries that package actually needs in `buildInputs`. Then add it to
`environment.systemPackages` or `home.packages`. That version is declarative,
reproducible, and survives a reinstall — `debinstall` is the exploratory step.

## Changes worth knowing are possible

- Restrict the wrap in step 7 to only the libs a package needs (the blanket
  `LD_LIBRARY_PATH` can shadow a library the binary bundles itself).
- Emit a warning listing `Depends:` entries with no obvious nixpkgs counterpart.
- Support `.tar.gz`/`.tar.xz` vendor tarballs by adding a `format` case.
- Add `--no-wrap` for packages that break under `makeWrapper`.
- Auto-install `.desktop` entries for GUI apps into a home-manager `xdg.desktopEntries`
  block instead of relying on the profile's `share/applications`.
