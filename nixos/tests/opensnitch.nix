{ pkgs, lib, ... }:
let
  monitorMethods = [
    # "ebpf"
    # "proc"
    # "ftrace"
    "audit"
  ];

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
{
  name = "opensnitch";

  meta = with pkgs.lib.maintainers; {
    maintainers = [ onny ];
  };

  nodes = lib.mergeAttrsList [
    {
      server = {
        networking.firewall.allowedTCPPorts = [ 80 ];
        services.caddy = {
          enable = true;
          virtualHosts."localhost".extraConfig = ''
            respond "Hello, world!"
          '';
        };
      };
      client_allowed_audit.security = {
        audit.enable = true;
        auditd.enable = true;
      };
      client_blocked_audit.security = {
        audit.enable = true;
        auditd.enable = true;
      };
    }
    (lib.listToAttrs (
      map (
        m:
        lib.nameValuePair "client_blocked_${m}" {
          security = {
            audit.enable = true;
            auditd.enable = true;
          };

          services.opensnitch = {
            enable = true;
            settings.DefaultAction = "deny";
            settings.ProcMonitorMethod = m;
            settings.LogLevel = 0;
          };

          system.replaceDependencies.replacements =
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

        }
      ) monitorMethods
    ))
    (lib.listToAttrs (
      map (
        m:
        lib.nameValuePair "client_allowed_${m}" {
          security = {
            audit.enable = true;
            auditd.enable = true;
          };

          system.replaceDependencies.replacements =
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

          services.opensnitch = {
            enable = true;
            settings.DefaultAction = "deny";
            settings.ProcMonitorMethod = m;
            settings.LogLevel = 0;
            rules = {
              curl = {
                name = "curl";
                enabled = true;
                action = "allow";
                duration = "always";
                operator = {
                  type = "simple";
                  sensitive = false;
                  operand = "process.path";
                  data = "${pkgs.curl}/bin/curl";
                };
              };
            };
          };
        }
      ) monitorMethods
    ))
  ];

  testScript =
    ''
      start_all()
      server.wait_for_unit("caddy.service")
      server.wait_for_open_port(80)
    ''
    + (
      lib.concatLines (
        map (m: ''
          client_blocked_${m}.wait_for_unit("opensnitchd.service")
          client_blocked_${m}.fail("curl http://server")

          client_allowed_${m}.wait_for_unit("opensnitchd.service")
          client_allowed_${m}.succeed("curl http://server")
        '') monitorMethods
      )
      + ''
        # make sure the kernel modules were actually properly loaded
        # client_blocked_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch\.o'")
        # client_blocked_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch-procs\.o'")
        # client_blocked_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch-dns\.o'")
        # client_allowed_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch\.o'")
        # client_allowed_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch-procs\.o'")
        # client_allowed_ebpf.succeed(r"journalctl -u opensnitchd --grep '\[eBPF\] module loaded: /nix/store/.*/etc/opensnitchd/opensnitch-dns\.o'")

        client_allowed_audit.fail(r"journalctl -u opensnitchd --grep '\"auditctl\": executable file not found'")
        client_blocked_audit.fail(r"journalctl -u opensnitchd --grep '\"auditctl\": executable file not found'")
      ''
    );
}
