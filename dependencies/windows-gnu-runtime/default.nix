# Windows target, Linux build host; use the same package authority as Blueprint.
let
  root = ../..;
  lock = builtins.fromJSON (builtins.readFile (root + /Blueprint.lock));
  pin = lock.nodes.${lock.nodes.${lock.root}.inputs.nixpkgs}.locked;
  pkgs = import (builtins.fetchTree pin) { system = "x86_64-linux"; };
  recipe = builtins.fromJSON (builtins.readFile ../windows-gnu-runtime.json);
  source = pkgs.lib.fileset.toSource {
    inherit root;
    fileset = pkgs.lib.fileset.unions [
      ../../Blueprint.lock ./default.nix ../windows-gnu-runtime.json
      ./DISCLAIMER.PD ./ucrt-inventory.json
      ../../scripts/build_windows_gnu_runtime.py ../../scripts/windows_runtime_validation.py
      ../../scripts/audit_windows_archive.py ../../scripts/build_glibc.py
      ../../scripts/dependency_archive.py ../../scripts/dependency_artifacts.py
      ../../scripts/nix_link_inputs.py ../../scripts/test_windows_gnu_runtime_artifact.py
      ../../test/dependencies/windows_gnu_runtime.cpp ../../test/dependencies/windows_gnu_runtime.rs
      ../../test/dependencies/windows_gnu_ubsan.c ../../test/dependencies/windows_gnu_compiler_rt.c
    ];
  };
  toolchain = pkgs.fetchurl { inherit (recipe.toolchain) url sha256; };
  builder = pkgs.buildEnv { name = "roc-gui-windows-runtime-builder"; paths = [ pkgs.python3 ]; };
in {
  runtime = pkgs.runCommand "roc-gui-windows-gnu-runtime-x64mingw" {
    nativeBuildInputs = [ pkgs.python3 ];
    dontFixup = true;
    NIX_BUILDER_ID = builtins.unsafeDiscardStringContext builder.drvPath;
    NIXPKGS_REV = pin.rev;
    NIXPKGS_NAR_HASH = pin.narHash;
    NIX_COMPONENT_SOURCE = toolchain;
  } ''
    export HOME="$TMPDIR/home"
    export PYTHONDONTWRITEBYTECODE=1
    mkdir -p "$HOME" "$out" work
    cd work
    python3 ${source}/scripts/build_windows_gnu_runtime.py --inside --output "$out"
  '';
  resource = pkgs.runCommand "roc-gui-windows-resource" {
    nativeBuildInputs = [ pkgs.python3 pkgs.zig_0_16 ];
    dontFixup = true;
  } ''
    export HOME="$TMPDIR/home"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/global"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/local"
    mkdir -p "$HOME"
    cp -r ${../../crates/host/windows} windows
    cd windows
    mkdir "$out"
    zig rc roc-gui.rc "$out/roc-gui.res"
  '';
}
