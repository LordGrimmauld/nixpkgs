{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.security.auditd;

  combined-plugin-packages = pkgs.buildEnv {
    name = "auditd-plugins";
    pathsToLink = [ "/etc/audit/plugins.d" ];
    paths = cfg.plugins;
    ignoreCollisions = true;
  };
in
{
  options.security.auditd = {
    enable = lib.mkEnableOption "the Linux Audit daemon";

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ pkgs.audit.out ];
      description = "plugin packages to register with auditd";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "audit=1" ];

    environment.systemPackages = [ pkgs.audit ];

    environment.etc."audit/plugins.d".source = "${combined-plugin-packages}/etc/audit/plugins.d";
    environment.etc."audit/auditd.conf".source = "${pkgs.audit.out}/etc/audit/auditd.conf";

    systemd.services.auditd = {
      description = "Linux Audit daemon";
      documentation = [ "man:auditd(8)" ];
      wantedBy = [ "sysinit.target" ];
      after = [
        "local-fs.target"
        "systemd-tmpfiles-setup.service"
      ];
      before = [
        "sysinit.target"
        "shutdown.target"
      ];
      conflicts = [ "shutdown.target" ];

      unitConfig = {
        ConditionVirtualization = "!container";
        ConditionSecurity = [ "audit" ];
        DefaultDependencies = false;
      };

      path = [ pkgs.audit ];

      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/log/audit";
        ExecStart = "${pkgs.audit}/bin/auditd -l -n -s nochange";
      };
    };
  };
}
