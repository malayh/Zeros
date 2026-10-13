{
  lib,
  pkgs,
  makeRustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  glib,
  gtk4,
  gtksourceview5,
  poppler_gi,
  fontconfig,
  gdk-pixbuf,
  gst_all_1,
  bubblewrap,
  ffmpeg,
  ffmpegthumbnailer,
  imagemagick,
  util-linux,
  gvfs,
  symlinkJoin,
}:
let
  # Strata's lockfile needs Rust 1.96; the pinned system nixpkgs has 1.95.
  rustOverlay = fetchFromGitHub {
    owner = "oxalica";
    repo = "rust-overlay";
    rev = "404b7a5537f0adc6e5c558a1b94612e683dec504";
    hash = "sha256-12C5ef8a3endLXBvLOVR/jynM9EHGgP1t+y5uBorwx4=";
  };
  toolchain = (pkgs.extend (import rustOverlay)).rust-bin.stable."1.96.0".minimal;
  rustPlatform = makeRustPlatform { cargo = toolchain; rustc = toolchain; };

  application = rustPlatform.buildRustPackage rec {
    pname = "strata";
    version = "1.0.0";

    src = fetchFromGitHub {
      owner = "lgse";
      repo = "strata";
      tag = "v${version}";
      hash = "sha256-dFNsFCnkeZs0VwmYRyu+6Jh8XxJzv+agUlP70Fdxa5Q=";
    };
    cargoHash = "sha256-vuhHierqb4WsMdg890NpkaztYnfsnck2FxMz5cPMwCQ=";

    nativeBuildInputs = [ pkg-config wrapGAppsHook4 glib ];
    buildInputs = [
      gtk4 gtksourceview5 poppler_gi fontconfig
      gst_all_1.gstreamer gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good gst_all_1.gst-libav
    ];

    # Keep the upstream trust checks; add our immutable Bubblewrap dependency.
    postPatch = ''
      substituteInPlace src/trusted_command.rs \
        --replace-fail '"/run/current-system/profile/bin",' \
          '"/run/current-system/profile/bin", "${bubblewrap}/bin",'
    '';

    STRATA_BUILD_COMMIT = "6662d8d4bd4cb3cdec3f10f918f3b4c92b18cdcc";
    STRATA_SANDBOX_ROOT = "/nix/store";
    STRATA_SANDBOX_PATH = lib.makeBinPath [ ffmpeg ffmpegthumbnailer imagemagick util-linux ];
    STRATA_SANDBOX_PRLIMIT = "${lib.getBin util-linux}/bin/prlimit";
    STRATA_SANDBOX_GDK_PIXBUF_MODULE_FILE = "${gdk-pixbuf}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache";

    preFixup = ''
      gappsWrapperArgs+=(--prefix GIO_EXTRA_MODULES : "${gvfs}/lib/gio/modules")
    '';
    postInstall = ''
      install -Dm644 data/io.github.lgse.Strata.desktop $out/share/applications/io.github.lgse.Strata.desktop
      install -Dm644 data/icons/scalable/apps/io.github.lgse.Strata.svg $out/share/icons/hicolor/scalable/apps/io.github.lgse.Strata.svg
      substituteInPlace $out/share/applications/io.github.lgse.Strata.desktop \
        --replace-fail 'Exec=strata ' "Exec=$out/bin/strata "
    '';
    # Preview sandbox tests require namespaces unavailable in Nix build sandboxes.
    doCheck = false;

    meta = {
      description = "A keyboard-first file manager for Linux";
      homepage = "https://github.com/lgse/strata";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "strata";
    };
  };
in
# Expose GVfs's D-Bus services and user units through the Home Manager profile.
symlinkJoin {
  name = "strata-${application.version}";
  paths = [ application gvfs ];
  inherit (application) meta;
}
