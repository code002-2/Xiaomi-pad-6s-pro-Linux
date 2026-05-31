{
  description = "Xiaomi Pad 6S Pro (Sheng) NixOS Flake - Rolling Release";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.sheng = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./configuration.nix
        ./sheng-hardware.nix
      ];
    };
  };
}
