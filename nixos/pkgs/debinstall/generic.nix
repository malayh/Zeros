{ nixpkgs, srcPath, pname, version, format, ignoreMissing ? "0" }:

let
  pkgs = import (/. + nixpkgs) { config.allowUnfree = true; };
  inherit (pkgs) lib stdenv;

  resolveFirst = names:
    lib.findFirst (x: x != null) null
      (map (p: lib.attrByPath (lib.splitString "." p) null pkgs) names);

  runtimeLibs = lib.filter (x: x != null) (map resolveFirst [
    [ "stdenv.cc.cc.lib" ] [ "glibc" ]
    [ "zlib" ] [ "xz" ] [ "bzip2" ] [ "openssl" ] [ "curl" ] [ "icu" ] [ "sqlite" ]
    [ "glib" ] [ "gtk3" ] [ "gtk4" ] [ "pango" ] [ "cairo" ] [ "gdk-pixbuf" ] [ "atk" ]
    [ "at-spi2-atk" ] [ "at-spi2-core" ]
    [ "nss" ] [ "nspr" ]
    [ "dbus" ] [ "expat" ]
    [ "fontconfig" ] [ "freetype" ] [ "harfbuzz" ]
    [ "alsa-lib" ] [ "libpulseaudio" ]
    [ "libdrm" ] [ "libgbm" "mesa" ] [ "libGL" ] [ "libglvnd" ] [ "vulkan-loader" ]
    [ "libxkbcommon" ]
    [ "systemd" ]
    [ "cups" ]
    [ "libsecret" ] [ "libnotify" ]
    [ "libuuid" ] [ "e2fsprogs" ] [ "pciutils" ] [ "libusb1" ]
    [ "libx11" "xorg.libX11" ]
    [ "libxcomposite" "xorg.libXcomposite" ]
    [ "libxdamage" "xorg.libXdamage" ]
    [ "libxext" "xorg.libXext" ]
    [ "libxfixes" "xorg.libXfixes" ]
    [ "libxrandr" "xorg.libXrandr" ]
    [ "libxrender" "xorg.libXrender" ]
    [ "libxtst" "xorg.libXtst" ]
    [ "libxi" "xorg.libXi" ]
    [ "libxcb" "xorg.libxcb" ]
    [ "libxcursor" "xorg.libXcursor" ]
    [ "libxscrnsaver" "xorg.libXScrnSaver" ]
    [ "libxshmfence" "xorg.libxshmfence" ]
  ]);

  # Kept out of buildInputs: qtbase's setup hook aborts when Qt5 and Qt6 both
  # appear as inputs, and Electron ships shims for both.
  searchOnlyLibs = lib.filter (x: x != null) (map resolveFirst [
    [ "qt6.qtbase" ]
    [ "libsForQt5.qtbase" "qt5.qtbase" ]
  ]);

  libPath = lib.makeLibraryPath runtimeLibs;
in
stdenv.mkDerivation {
  inherit pname version;

  src = /. + srcPath;

  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ]
    ++ lib.optional (format == "deb") pkgs.dpkg
    ++ lib.optional (format == "rpm") pkgs.rpmextract;

  buildInputs = runtimeLibs;

  autoPatchelfIgnoreMissingDeps =
    if ignoreMissing == "1" then true else [ "libc.musl-x86_64.so.1" ];
  dontStrip = true;
  dontBuild = true;
  dontConfigure = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir -p unpacked
    cd unpacked
    ${if format == "deb" then "dpkg-deb -x \"$src\" ." else "rpmextract \"$src\""}
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out" "$out/bin"

    if [ -d usr ]; then
      cp -a usr/. "$out/"
    fi
    if [ -d "$out/local" ]; then
      cp -a "$out/local/." "$out/"
      rm -rf "$out/local"
    fi

    for d in opt srv etc lib var; do
      if [ -d "$d" ]; then
        mkdir -p "$out/$d"
        cp -a "$d/." "$out/$d/"
      fi
    done

    find "$out" -type l | while read -r l; do
      t=$(readlink "$l")
      case "$t" in
        /usr/*) ln -sfn "$out/''${t#/usr/}" "$l" ;;
        /opt/*|/etc/*|/srv/*) ln -sfn "$out$t" "$l" ;;
      esac
    done

    if [ -d "$out/share/applications" ]; then
      find "$out/share/applications" -name '*.desktop' -print0 \
        | xargs -0 -r sed -i -e "s|/usr/|$out/|g" -e "s|/opt/|$out/opt/|g"
    fi

    if [ -d "$out/opt" ]; then
      find "$out/opt" -mindepth 2 -maxdepth 4 -type f -perm -111 \
        \( -path '*/bin/*' -o -name "$pname" \) -print0 \
        | while IFS= read -r -d "" f; do
            ln -sfn "$f" "$out/bin/$(basename "$f")"
          done
    fi

    for f in "$out"/bin/*; do
      [ -e "$f" ] || continue
      wrapProgram "$f" --prefix LD_LIBRARY_PATH : "${libPath}"
    done

    runHook postInstall
  '';

  preFixup = lib.concatMapStringsSep "\n"
    (p: "addAutoPatchelfSearchPath --no-recurse ${lib.getLib p}/lib")
    searchOnlyLibs;

  meta.mainProgram = pname;
}
