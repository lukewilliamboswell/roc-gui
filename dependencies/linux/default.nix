# One package authority: the root nixpkgs input of Blueprint.lock.
let
  root = ../..;
  lock = builtins.fromJSON (builtins.readFile (root + /Blueprint.lock));
  pin = lock.nodes.${lock.nodes.${lock.root}.inputs.nixpkgs}.locked;
  pkgs = import (builtins.fetchTree pin) { system = "x86_64-linux"; };
  lib = pkgs.lib;
  # The component recipe requires Meson 1.12; nixpkgs supplies 1.10.2.
  # Keep its packaging/toolchain and override only the reviewed upstream source.
  meson = pkgs.meson.overrideAttrs (old: {
    version = "1.12.0";
    # Nix's compiler wrapper injects fortify flags; this upstream fixture
    # asserts the unwrapped compiler's exact flags. Retain the other tests.
    preCheck = (old.preCheck or "") + ''
      rm -r 'test cases/common/282 -D_FORTIFY_SOURCE=2 and -O0'
    '';
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/48/91/d58a3eb45ed54bf32b96806dd2f4efd407f7a9675953e15e8ef257840a0d/meson-1.12.0.tar.gz";
      sha256 = "88afe0c20e52030218924ac37d0c81c59b4b5f3ae3752c8c6d7470c7d365886c";
    };
  });
  libraries = with pkgs; [ zlib bzip2 libpng harfbuzz brotli libxcb alsa-lib ];
  tools = with pkgs; [ stdenv.cc python3 zig_0_16 cmake gnumake pkg-config ninja bison binutils patchelf meson ];
  builder = pkgs.buildEnv { name = "roc-gui-linux-builder"; paths = tools ++ libraries; };
  source = name: script: lib.fileset.toSource {
    root = root;
    fileset = lib.fileset.unions ([
      ../../Blueprint.lock ./default.nix
      (root + "/dependencies/${if name == "alsa" then "alsa-interface" else name}.json")
      (root + "/scripts/${script}.py")
      ../../scripts/nix_link_inputs.py ../../scripts/dependency_archive.py ../../scripts/dependency_artifacts.py
    ] ++ (if name == "unwind" then [
      ../../scripts/build_glibc.py ../../scripts/test_unwind_rust.py
      ../../test/dependencies/unwind.cpp ../../test/dependencies/unwind.rs ../../test/dependencies/unwind-rust.c
    ] else [ (root + "/test/dependencies/${name}.c") ])
    ++ lib.optionals (name == "glibc") [ ../glibc ]
    ++ lib.optionals (name == "freetype") [ ./zig-toolchain.cmake ]
    ++ lib.optionals (name == "xkbcommon") [ ../xkbcommon ]);
  };
  fetch = item: pkgs.fetchurl { inherit (item) url sha256; };
  recipe = name: builtins.fromJSON (builtins.readFile (root + "/dependencies/${name}.json"));
  mk = name: script: input: let tree = source name script; in pkgs.runCommand "roc-gui-${name}-x64glibc" {
    nativeBuildInputs = tools;
    buildInputs = libraries;
    dontFixup = true;
    NIX_BUILDER_ID = builtins.unsafeDiscardStringContext builder.drvPath;
    NIXPKGS_REV = pin.rev;
    NIXPKGS_NAR_HASH = pin.narHash;
    NIX_PROBE_LOADER = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
    NIX_PROBE_LIBRARIES = lib.makeLibraryPath (libraries ++ [ pkgs.glibc pkgs.libXau pkgs.libXdmcp ]);
    NIX_ALSA_PROVIDER = "${pkgs.alsa-lib}/lib/libasound.so.2";
    NIX_COMPONENT_SOURCE = if input == null then "" else toString (fetch input);
    NIX_COMPONENT = name;
  } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$out" work
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
    export PYTHONDONTWRITEBYTECODE=1
    export PATH="${tree}/dependencies/xkbcommon:$PATH"
    cd work
    python3 ${tree}/scripts/${script}.py --inside --output "$out"
  '';
in {
  alsa = mk "alsa" "build_alsa_interface" null;
  freetype = mk "freetype" "build_freetype" (recipe "freetype").source;
  glibc = mk "glibc" "build_glibc" (recipe "glibc").toolchain;
  unwind = mk "unwind" "build_unwind" (recipe "unwind").toolchain;
  xkbcommon = mk "xkbcommon" "build_xkbcommon" (recipe "xkbcommon").source;
}
