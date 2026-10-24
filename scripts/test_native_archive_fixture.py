"""Current-format native archive inputs shared by producer policy tests."""

from dependency_archive import digest
from dependency_artifacts import nix_source_inventory


def current_native(name, files):
    payload = {path: data for path, data in files.items() if not path.startswith("sources/")}
    for path in nix_source_inventory(name):
        payload[path] = files.get(path, b"reviewed native source")
    prefix = f"sources/{name}/"
    build = {"builder_derivation": "/nix/store/" + "a" * 32 + "-builder.drv",
             "nixpkgs_revision": "b" * 40, "nixpkgs_nar_hash": "sha256-" + "A" * 43 + "=",
             "nixpkgs_pin_sha256": digest(payload[prefix + "dependencies/nixpkgs-pin.nix"]),
             "nix_recipe_sha256": digest(payload[prefix + "dependencies/linux/default.nix"])}
    return {"schema_version": 4, "name": name, "target": "x64glibc", "version": "test", "build": build}, payload
