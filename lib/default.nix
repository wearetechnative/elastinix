{lib, ...}:
let
  base64 = import ./base64.nix {inherit lib;};
in
{
  toBase64 = (text: base64.toBase64 text);
  tf_command = import ./tf_command.nix;
}

