{
  description = "Fly.io deployment for org-agenda-api";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Direct dependency on org-agenda-api for mkContainer
    org-agenda-api = {
      url = "github:colonelpanic8/org-agenda-api";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Dotfiles provides tangled org-config elisp files
    dotfiles = {
      url = "github:colonelpanic8/dotfiles?dir=nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, agenix, dotfiles, org-agenda-api }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Get tangled config files from dotfiles
        tangledConfig = dotfiles.packages.${system}.org-agenda-custom-config;

        # Combine tangled config with our loader
        orgAgendaCustomConfig = pkgs.runCommand "org-agenda-custom-config" {} ''
          mkdir -p $out

          # Copy tangled files from dotfiles
          cp ${tangledConfig}/*.el $out/ 2>/dev/null || true

          # Add our custom-config.el loader
          cp ${./custom-config.el} $out/custom-config.el
        '';

        # Build the container
        container = org-agenda-api.lib.${system}.mkContainer {
          customElispFile = "${orgAgendaCustomConfig}/custom-config.el";
        };
      in
      {
        packages = {
          inherit container;
          default = container;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Fly.io CLI
            pkgs.flyctl

            # Secrets management
            agenix.packages.${system}.default
            pkgs.age
            pkgs.ssh-to-age

            # Git
            pkgs.git

            # For debugging/API interaction
            pkgs.jq
            pkgs.just
            pkgs.curl
          ];

          shellHook = ''
            echo ""
            echo "org-agenda-api Fly.io deployment shell"
            echo ""
            echo "Commands:"
            echo "  just --list             - Show available API commands"
            echo "  ./deploy.sh             - Deploy to Fly.io"
            echo "  flyctl                  - Fly.io CLI"
            echo "  agenix -e <file>        - Edit encrypted secrets"
            echo ""
          '';
        };
      });
}
