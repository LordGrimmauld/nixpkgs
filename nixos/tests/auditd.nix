{ lib, ... }:
{
  name = "auditd";

  meta = {
    maintainers = with lib.maintainers; [ grimmauld ];
  };

  nodes.machine =
    { lib, pkgs, ... }:
    {
      security.audit.enable = true;
      security.auditd = {
        enable = true;
        plugins.af_unix.active = true;
        # plugins.remote.active = true; # needs configuring a remote server for logging
        # plugins.filter.active = true; # needs configuring allowlist/denylist
        plugins.syslog.active = true;
      };

      system.replaceDependencies.replacements =
        let
          audit' = pkgs.audit.overrideAttrs (old: {
            src = pkgs.fetchFromGitHub {
              owner = "linux-audit";
              repo = "audit-userspace";
              tag = "v4.0.5";
              hash = "sha256-SgMt1MmcH7r7O6bmJCetRg3IdoZXAXjVJyeu0HRfyf8=";
            };
            patches = old.patches or [ ] ++ [
              ../../pkgs/by-name/au/audit/0001-auditd-Avoid-blocking-on-open-syscall.patch
              ../../pkgs/by-name/au/audit/0002-auditd-support-loading-plugin-configs-from-symlinks.patch
              ../../pkgs/by-name/au/audit/0003-auditd-use-O_PATH-to-avoid-blocking-on-special-files.patch
            ];

            env.NIX_CFLAGS_COMPILE = "-fsanitize=address";
          });
        in
        [
          {
            oldDependency = pkgs.audit.bin;
            newDependency = audit'.bin;
          }
        ];
    };

  testScript = ''
    start_all()
    machine.wait_for_unit("auditd.service")
    machine.succeed("stat /var/run/audispd_events")
  '';
}
