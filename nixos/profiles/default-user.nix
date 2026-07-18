# ---
# Module: Default Test User
# Description: Provides the disposable user used by repository-built test images
# Scope: System
# Notes:
# - Downstream dotfiles should define their own users instead of importing this profile.
# ---

{ vars, ... }:

{
  users.users.${vars.username} = {
    isNormalUser = true;
    initialPassword = vars.userPassword;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "input" "render" ];
  };
  users.users.root.initialPassword = vars.rootPassword;

  services.getty.autologinUser = vars.username;
  services.openssh.settings = {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };
}
