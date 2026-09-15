{
  description = "Native, state-driven GUI applications in Roc, hosted by GPUI.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # Records the nightly that platform/main.roc pins. Merging
    # roc-lang/roc-overlay#28 moves this to the overlay's default branch.
    roc-overlay.url = "github:roc-lang/roc-overlay/7338b792527a5025fdcccc431c0bb6aacdd5e240";
    roc-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, rust-overlay, roc-overlay, ... }:
    let
      lib = nixpkgs.lib;
      # The hosts the platform itself targets: x64glibc and arm64mac.
      systems = [ "x86_64-linux" "aarch64-darwin" ];

      pkgsFor = lib.genAttrs systems (system:
        import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        });

      # Both toolchain pins belong to the repository, so this flake reads them
      # instead of repeating them: rust-toolchain.toml names the Rust channel,
      # profile and components, and the platform header names the Roc nightly
      # that every maintained application shares.
      rocNightly =
        let
          header = builtins.readFile ./platform/main.roc;
          line = "[[:space:]]*roc:[[:space:]]*\"([^\"]+)\"[[:space:]]*,?[[:space:]]*";
          matched = builtins.filter (m: m != null)
            (map (builtins.match line) (lib.splitString "\n" header));
        in
        if matched == [ ]
        then throw "platform/main.roc carries no roc: pin for this shell to honour"
        else builtins.head (builtins.head matched);

      rocFor = system:
        let
          releases = roc-overlay.packages.${system} or { };
        in
        if lib.hasAttr rocNightly releases then
          lib.getAttr rocNightly releases
        else
          throw ("roc-overlay records no " + rocNightly
            + "; advance it with `nix flake lock --update-input roc-overlay`"
            + " once that nightly reaches its default branch");

      # Running an application on a host with no generic Linux loader
      #
      # Every external linker input arrives from a pinned, verified release that
      # scripts/prepare_dependencies.py downloads, so nothing here builds one.
      # A finished application is still an ordinary dynamically linked
      # x86_64-linux-gnu binary: it asks the kernel for a loader at
      # /lib64/ld-linux-x86-64.so.2 and names libasound, libfreetype and
      # libxkbcommon by soname. Distribution hosts answer both from the system,
      # which is why CI only apt-installs the libraries.
      #
      # NixOS answers that loader path with a stub that prints an explanation
      # and exits 127, so `roc path/to/main.roc` and `./counter` cannot start.
      # The shell provides roc-gui-native, which runs the command it is given
      # inside a mount namespace whose /lib64 holds a real loader, and runs it
      # unchanged on a host that already has one. It provisions a path; it
      # confines nothing and grants nothing an application could observe.
      #
      # Deliberately opt-in. Re-execing the interactive login shell into the
      # namespace would let the documented commands run unprefixed, but it
      # replaces the user's terminal session and damages its state, so the
      # command is spelled out instead of smuggled in. Nothing here asks you to
      # change your system configuration; NixOS's own programs.nix-ld option
      # serves the same need system-wide if you prefer to configure it.
      #
      #   roc-gui-native ./counter                 one application
      #   roc-gui-native roc examples/x/main.roc   build and run in place
      #   roc-gui-native bash                      a whole session, on request
      #   roc-gui-native --needs-loader            does this host need the view?
      loader = pkgs:
        pkgs.stdenv.mkDerivation {
          name = "roc-gui-loader";
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p "$out"
            ln -s ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 "$out/ld-linux-x86-64.so.2"
          '';
        };

      nativeRunner = pkgs:
        pkgs.writeShellScriptBin "roc-gui-native" ''
          needs_loader() {
            case $(readlink -f /lib64/ld-linux-x86-64.so.2 2>/dev/null) in
              "" | *-stub-ld-*) return 0 ;;
              *) return 1 ;;
            esac
          }

          if [ "$1" = --needs-loader ]; then
            needs_loader
            exit $?
          fi

          needs_loader || exec "$@"
          # No --new-session, so `roc-gui-native bash` keeps the caller's
          # controlling terminal and job control.
          exec ${pkgs.bubblewrap}/bin/bwrap \
            --die-with-parent \
            --bind / / --ro-bind ${loader pkgs} /lib64 \
            --dev-bind /dev /dev --proc /proc \
            "$@"
        '';

      shellFor = system: pkgs:
        let
          hostRust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          roc = rocFor system;
          onLinux = lib.optionals pkgs.stdenv.hostPlatform.isLinux;
          # What an application resolves by soname once it is running: the
          # providers of the released link inputs, and what GPUI opens.
          runtimeLibraries = [
            pkgs.alsa-lib
            pkgs.freetype
            pkgs.libxkbcommon
            pkgs.libxcb
            pkgs.wayland
            pkgs.libdrm
            pkgs.mesa
            pkgs.vulkan-loader
            pkgs.dbus
            pkgs.udev
            pkgs.libusb1
            pkgs.fontconfig
          ];
        in
        pkgs.mkShell {
          packages = [
            hostRust
            pkgs.zig_0_16
            pkgs.python3
            pkgs.git
            pkgs.pkg-config
            roc
          ] ++ onLinux ([ (nativeRunner pkgs) ] ++ runtimeLibraries);

          LD_LIBRARY_PATH = lib.makeLibraryPath (onLinux runtimeLibraries);

          shellHook = ''
            printf 'roc-gui: rust %s, zig %s, %s\n' \
              "${lib.getVersion hostRust}" "${pkgs.zig_0_16.version}" \
              "$(${lib.getExe roc} version)" >&2
          ''
          + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            if ${lib.getExe (nativeRunner pkgs)} --needs-loader; then
              printf 'roc-gui: %s\n' \
                'start applications with roc-gui-native: no generic Linux loader here' >&2
            fi
          '';
        };
    in
    {
      devShells = lib.genAttrs systems (system:
        { default = shellFor system pkgsFor.${system}; });

      # Builds the compiler this flake selects and rejects an identity that
      # disagrees with the pin the maintained roots require.
      checks = lib.genAttrs systems (system: {
        roc-pin = (pkgsFor.${system}.runCommand "roc-gui-roc-pin" { } ''
          version="$(${lib.getExe (rocFor system)} version)"
          case "$version" in
            *${rocNightly}*) ;;
            *) echo "expected ${rocNightly}, reported: $version" >&2; exit 1 ;;
          esac
          mkdir -p "$out"
          printf '%s\n' "$version" > "$out/version"
        '');
      });
    };
}
