{ lib, ... }:
{
  name = "auditd";

  meta = {
    maintainers = with lib.maintainers; [ grimmauld ];
  };

  nodes.machine = {
    security.audit.enable = true;
    security.auditd = {
      enable = true;
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("auditd.service")
    machine.succeed("stat /var/run/audispd_events")
  '';
}
