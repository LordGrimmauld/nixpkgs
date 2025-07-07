{ lib, config, ... }:
let
  cfg = config.security.restrict-suid-sgid;
in
{
  meta.maintainers = with lib.maintainers; [ grimmauld ];

  options.security.restrict-suid-sgid = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When enabled, it will be disallowed by default for
        services to create SUID/SGID files. Some services
        might need an explicit exception to work correctly.
      '';
    };

    allowedServices = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [
        "suid-sgid-wrappers"
        "systemd-tmpfiles-setup"
        "systemd-tmpfiles-resetup"
      ];
      description = ''
        List of services to be allowed to create SUID/SGID files.
        On a normal nixos system, `suid-sgid-wrappers` is required
        to create suid files for e.g. sudo and fuse to work correctly,
        while `systemd-tmpfiles-setup` and `systemd-tmpfiles-resetup`
        is being used by systemd internally to fix file permissions.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.extraConfig = "DefaultRestrictSUIDSGID=yes";

    systemd.services = lib.genAttrs cfg.allowedServices (_: {
      serviceConfig.RestrictSUIDSGID = false;
    }); # TODO: move into services explicitly
  };
}
