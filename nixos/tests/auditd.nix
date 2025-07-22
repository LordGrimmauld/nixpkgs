{ lib, ... }:
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

      security.auditd = {
        enable = true;
        plugins.af_unix.active = true;
        # plugins.syslog.active = true;
        # plugins.remote.active = true; # needs configuring a remote server for logging
        # plugins.filter.active = true; # needs configuring allowlist/denylist
      };

      security.polkit.enable = true;

      environment.systemPackages = [ pkgs.audit-testsuite.runner ];
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
