{
  description = "Fly.io deployment for org-agenda-api";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    org-agenda-api = {
      url = "github:colonelpanic8/org-agenda-api";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # For advanced dotfiles integration, see:
    # https://github.com/colonelpanic8/colonelpanic-org-agenda-api
  };

  outputs = { self, nixpkgs, flake-utils, agenix, org-agenda-api }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Build the container with local custom-config.el
        container = org-agenda-api.lib.${system}.mkContainer {
          customElispFile = ./custom-config.el;
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

            # OpenTofu for infrastructure
            pkgs.opentofu

            # Secrets management
            agenix.packages.${system}.default
            pkgs.age
            pkgs.ssh-to-age

            # Git
            pkgs.git

            # Docker for container builds
            pkgs.docker

            # For debugging/API interaction
            pkgs.jq
            pkgs.just
            pkgs.curl
          ];

          shellHook = ''
            # Decrypt secrets if they exist
            if [ -f "./decrypt-secrets.sh" ]; then
              source ./decrypt-secrets.sh 2>/dev/null || true
            fi

            echo ""
            echo "org-agenda-api deployment shell"
            echo ""
            echo "Quick start:"
            echo "  ./setup.sh              - Interactive setup (if not done)"
            echo "  tofu init && tofu apply - Deploy infrastructure"
            echo "  ./deploy.sh             - Build and deploy container"
            echo ""
            echo "Other commands:"
            echo "  just --list             - Show API test commands"
            echo "  flyctl logs             - View deployment logs"
            echo "  agenix -e <file>        - Edit encrypted secrets"
            echo ""
          '';
        };
      });
}
