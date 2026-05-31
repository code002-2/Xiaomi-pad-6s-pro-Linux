{
  description = "Xiaomi Pad 6S Pro (Sheng) NixOS Flake";

  inputs = {
    # 使用 NixOS 24.05 稳定版分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.sheng = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ./configuration.nix
        ./sheng-hardware.nix
        # 引入官方的 tarball 生成模块，方便我们在 Actions 里转成 ext4
        "${nixpkgs}/nixos/modules/installer/cd-dvd/system-tarball.nix"
      ];
    };
  };
}
