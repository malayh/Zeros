{ writeShellApplication, dpkg, rpm, nix, coreutils, path }:

writeShellApplication {
  name = "debinstall";
  runtimeInputs = [ dpkg rpm nix coreutils ];
  text = ''
    generic=${./generic.nix}
    nixpkgs=${path}

    usage() {
      cat <<'EOF'
    debinstall — install .deb / .rpm packages into your Nix profile

      debinstall <file>                install a package
      debinstall install <file>        same, explicit
      debinstall remove <name>         uninstall it again
      debinstall list                  show what is installed

    Options:
      --ignore-missing   build even if some shared libraries stay unresolved

    Maintainer scripts are not run: services, system users, kernel modules
    and setuid binaries will not work.
    EOF
    }

    cmd=''${1-}
    case "$cmd" in
      ""|-h|--help) usage; exit 0 ;;
      list) shift; nix profile list; exit 0 ;;
      remove|uninstall) shift; nix profile remove "$@"; exit 0 ;;
      install|add) shift ;;
      *) : ;;
    esac

    file=""
    ignore=0
    for arg in "$@"; do
      case "$arg" in
        --ignore-missing) ignore=1 ;;
        *) file=$arg ;;
      esac
    done

    if [ -z "$file" ]; then
      usage
      exit 1
    fi
    file=$(realpath -e "$file")

    case "$file" in
      *.deb)
        format=deb
        pname=$(dpkg-deb -f "$file" Package)
        version=$(dpkg-deb -f "$file" Version)
        ;;
      *.rpm)
        format=rpm
        pname=$(rpm -qp --nosignature --queryformat '%{NAME}' "$file")
        version=$(rpm -qp --nosignature --queryformat '%{VERSION}-%{RELEASE}' "$file")
        ;;
      *)
        echo "debinstall: expected a .deb or .rpm file, got $file" >&2
        exit 1
        ;;
    esac

    pname=''${pname//[^A-Za-z0-9._+-]/-}
    version=''${version//[^A-Za-z0-9._+-]/-}

    echo "debinstall: building $pname $version"
    out=$(nix build --impure --no-link --print-out-paths \
      --file "$generic" \
      --argstr nixpkgs "$nixpkgs" \
      --argstr srcPath "$file" \
      --argstr pname "$pname" \
      --argstr version "$version" \
      --argstr format "$format" \
      --argstr ignoreMissing "$ignore")

    nix profile add "$out"

    echo "debinstall: installed $pname -> $out"
    if [ -d "$out/bin" ]; then
      echo "debinstall: commands:"
      ls -1 "$out/bin"
    fi
  '';
}
