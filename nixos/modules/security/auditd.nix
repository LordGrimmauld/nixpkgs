{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.security.auditd;

  plugin_conf = lib.types.submodule {
    options = {
      active = lib.mkEnableOption "whether to enable this plugin";
      direction = lib.mkOption {
        type = lib.types.enum [
          "in"
          "out"
        ];
        default = "out";
        description = ''
          The option is dictated by the plugin.  In or out are the only choices.
          You cannot make a plugin operate in a way it wasn't  designed just by
          changing this option. This option is to give a clue to the event dispatcher
          about which direction events flow. NOTE: inbound events are not supported yet.
        '';
      };
      path = lib.mkOption {
        type = lib.types.path;
        description = "This is the absolute path to the plugin executable.";
      };
      type = lib.mkOption {
        type = lib.types.enum [ "always" ];
        default = "always";
        description = ''
          This  tells the dispatcher how the plugin wants to be run. There is only
          one valid option, `always`, which means the plugin is external and should
          always be run. The default is always since there are no more builtin plugins.
        '';
      };
      args = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.nonEmptyStr);
        default = null;
        description = ''
          This allows you to pass arguments to the child program.
          Generally plugins do not take arguments and have their own
          config file that instructs them how they should be configured.
        '';
      };
      format = lib.mkOption {
        type = lib.types.enum [
          "binary"
          "string"
        ];
        default = "string";
        description = ''
          Binary passes the data exactly as the audit event dispatcher gets it from
          the audit  daemon. The string option tells the dispatcher to completely change
          the event into a string suitable for parsing with the audit parsing library.
        '';
      };
      config_file = lib.mkOption {
        type = lib.types.nullOr lib.types.pathInStore;
        default = null;
        description = "the path to a plugin-specific config file to link to /etc/audit/<plugin>.conf";
      };
    };
  };

  prepareConfigValue =
    v:
    if lib.isBool v then
      (if v then "yes" else "no")
    else if lib.isList v then
      lib.concatStringsSep " " (map prepareConfigValue v)
    else
      builtins.toString v;
  prepareConfigText =
    conf:
    lib.concatLines (
      lib.mapAttrsToList (k: v: if v == null then "#${k} =" else "${k} = ${prepareConfigValue v}") conf
    );
in
{
  options.security.auditd = {
    enable = lib.mkEnableOption "the Linux Audit daemon";

    config = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          bool
          nonEmptyStr
          path
          int
        ]);
      default = { };
      description = "key/value pairs of config options to write to /etc/audit/auditd.conf";
    };

    plugins = lib.mkOption {
      type = lib.types.attrsOf plugin_conf;
      default = { };
      description = "plugin definitions to register with auditd";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [ "audit=1" ];

    environment.systemPackages = [ pkgs.audit ];

    security.auditd.config.plugin_dir = "/etc/audit/plugins.d";

    environment.etc =
      {
        "audit/auditd.conf".source = "${pkgs.audit.out}/etc/audit/auditd.conf"; # TODO: serialize full config
      }
      // (lib.mapAttrs' (
        n: v:
        lib.nameValuePair "audit/plugins.d/${n}.conf" {
          text = prepareConfigText (lib.removeAttrs v [ "config_file" ]);
        }
      ) cfg.plugins)
      // (lib.mapAttrs' (
        n: v: lib.nameValuePair "audit/audisp-${n}.conf" { source = v.path; }
      ) cfg.plugins);

    security.auditd.plugins = {
      af_unix = {
        path = lib.getExe' pkgs.audit "audisp-af_unix";
        args = [
          "0640"
          "/var/run/audispd_events"
          "string"
        ];
        format = "binary";
      };
      remote = {
        path = lib.getExe' pkgs.audit "audisp-remote";
        config_file = "${pkgs.audit}/etc/audit/audisp-remote.conf";
      };
      filter = {
        path = lib.getExe' pkgs.audit "audisp-filter";
        args = [
          "allowlist"
          "/etc/audit/audisp-filter.conf"
          (lib.getExe' pkgs.audit "audisp-syslog")
          "LOG_USER"
          "LOG_INFO"
          "interpret"
        ];
        config_file = "${pkgs.audit}/etc/audit/audisp-filter.conf";
      };
      syslog = {
        path = lib.getExe' pkgs.audit "audisp-syslog";
        args = [ "LOG_INFO" ];
      };
    };

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
