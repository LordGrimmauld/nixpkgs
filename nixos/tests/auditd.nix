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
              ../../pkgs/by-name/au/audit/write-debug-logs.patch
              ../../pkgs/by-name/au/audit/allow-symlink-plugin-configs.patch
            ];

            postInstall = ''
              for plugin_def in $out/etc/audit/plugins.d/*.conf; do
                substituteInPlace "$plugin_def" \
                  --replace-fail "/sbin/" "$bin/bin/" \
                  --replace-warn "active = no" "active = yes"
              done
            '';
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
    machine.succeed("stat /var/run/audispd_events")
  '';
}
