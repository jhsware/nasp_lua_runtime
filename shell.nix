let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
        "claude-code-bin"
      ];
    };
  };

  isMacOS = builtins.match ".*-darwin" pkgs.stdenv.hostPlatform.system != null;
in pkgs.mkShell rec {
  name = "dart";

  buildInputs = with pkgs; [   
    pkgs.claude-code-bin # This is the package containing the Anthropic binary distribution of claude code
    pkgs.openssl         # Required to generate client certificates
    pkgs.dart
    pkgs.gnupg           # For GPG commit signing
    pkgs.pinentry-curses # For GPG passphrase entry (terminal-based)
  ] ++ (if !isMacOS then [
  ] else []);

  shellHook = ''
    # Set up GPG environment for commit signing
    export GPG_TTY=$(tty)
    
    # Note: GPG tests create their own temporary GNUPGHOME
    # For real GPG signing, you'll need to set up keys:
    #   gpg --full-generate-key
    #   git config --global user.signingkey YOUR_KEY_ID
  '';
}
