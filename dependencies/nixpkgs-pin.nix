# The locked `default` package input of Blueprint.lock, as `builtins.fetchTree`
# takes it. The lock is an S-expression; only this node's `locked` fields are
# read, and `narHash` makes the fetch fail if they were read wrongly.
lockFile:
let
  text = builtins.readFile lockFile;
  after = separator: string: builtins.elemAt (builtins.split separator string) 2;
  before = separator: string: builtins.head (builtins.split separator string);
  nodes = after "\\(name \"nodes\"\\)" text;
  node = before "\\(name \"original\"\\)" (after "\\(name \"default\"\\)" nodes);
  field = kind: name:
    let found = builtins.match ".*\\(name \"${name}\"\\)[[:space:]]*\\(value \\(${kind} \"?([^\")]*)\"?\\)\\).*" node;
    in if found == null then throw "Blueprint.lock: no locked ${name} for the default package input" else builtins.head found;
in {
  type = field "Str" "type";
  owner = field "Str" "owner";
  repo = field "Str" "repo";
  rev = field "Str" "rev";
  narHash = field "Str" "narHash";
  lastModified = builtins.fromJSON (field "Int" "lastModified");
}
