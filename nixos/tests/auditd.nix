{ lib, pkgs, ... }:
let
  inherit (import ./ssh-keys.nix pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey
    ;
in
{
  name = "auditd";

  meta = {
    maintainers = with lib.maintainers; [ grimmauld ];
  };

  nodes.machine =
    { pkgs, ... }:
    {
      security.audit.enable = true;
      security.audit.backlogLimit = 8192;

      # https://github.com/linux-audit/audit-testsuite/blob/5a10451642ac1ba2fa4b31c06a21cf9aa2d38b66/tests/amcast_joinpart/test#L86
      # tests use LC_TIME=en_DK.utf8 to force ISO 8601 date format
      i18n.extraLocales = [ "en_DK.UTF-8/UTF-8" ];

      security.pam.services.systemd-run0.setLoginUid = true; # we need a login session for the test suite to run. This convinces pam to create a new session for the unit spawned by run0

      # don't disable SELinux support
      security.lsm = lib.mkForce [ ];

      security.auditd = {
        enable = true;
        plugins.af_unix.active = true;
        # plugins.syslog.active = true;
        # plugins.remote.active = true; # needs configuring a remote server for logging
        # plugins.filter.active = true; # needs configuring allowlist/denylist
      };

      environment.systemPackages = [ pkgs.audit-testsuite.runner ];

      system.replaceDependencies.replacements =
        let
          audit' = pkgs.audit.overrideAttrs (old: {
            configureFlags = old.configureFlags or [ ] ++ [ "--with-io_uring" ];
            patches = old.patches or [] ++ [ ../../pkgs/by-name/au/audit/ausearch-allow-symlinks.patch ];
          });
        in
        builtins.concatMap
          (
            { oldDependency, newDependency }:
            assert oldDependency.outputs == newDependency.outputs;
            builtins.map (out: {
              oldDependency = oldDependency.${out};
              newDependency = newDependency.${out};
            }) oldDependency.outputs
          )
          (
            lib.singleton {
              oldDependency = pkgs.audit;
              newDependency = audit';
            }
          );
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("auditd.service")
    machine.wait_for_unit("network.target") # netfilter test requires network
    machine.succeed("stat /var/run/audispd_events")
    machine.succeed("stat /var/log/audit/audit.log")
    machine.succeed("stat /etc/audit/auditd.conf")

    # we need a valid session to which we can send commands, so we use run0
    machine.succeed("run0 --pty audit-testsuite-runner")
  '';
}
