import ../make-test-python.nix (
  { pkgs, lib, ... }:
  let
    helloProfileContents = ''
      abi <abi/4.0>,
      include <tunables/global>
      profile hello ${lib.getExe pkgs.hello} {
        include <abstractions/base>
      }
    '';
  in
  {
    name = "apparmor";
    meta.maintainers = with lib.maintainers; [ julm ];

    nodes.machine =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      {
        security.apparmor = {
          enable = lib.mkDefault true;

          policies.hello = {
            # test profile enforce and content definition
            state = "enforce";
            profile = helloProfileContents;
          };

          policies.sl = {
            # test profile complain and path definition
            state = "complain";
            path = ./sl_profile;
          };
        };
      };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      with subtest("AppArmor profiles are loaded"):
          machine.succeed("systemctl status apparmor.service")

      # AppArmor securityfs
      with subtest("AppArmor securityfs is mounted"):
          machine.succeed("mountpoint -q /sys/kernel/security")
          machine.succeed("cat /sys/kernel/security/apparmor/profiles")

      # Test apparmorRulesFromClosure by:
      # 1. Prepending a string of the relevant packages' name and version on each line.
      # 2. Sorting according to those strings.
      # 3. Removing those prepended strings.
      # 4. Using `diff` against the expected output.
      with subtest("apparmorRulesFromClosure"):
          machine.succeed(
              "${pkgs.diffutils}/bin/diff -u ${
                pkgs.writeText "expected.rules" (import ./makeExpectedPolicies.nix { inherit pkgs; })
              } ${
                pkgs.runCommand "actual.rules" { preferLocalBuild = true; } ''
                  ${pkgs.gnused}/bin/sed -e 's:^[^ ]* ${builtins.storeDir}/[^,/-]*-\([^/,]*\):\1 \0:' ${
                    pkgs.apparmorRulesFromClosure {
                      name = "ping";
                      additionalRules = [ "x $path/foo/**" ];
                    } [ pkgs.libcap ]
                  } |
                  ${pkgs.coreutils}/bin/sort -n -k1 |
                  ${pkgs.gnused}/bin/sed -e 's:^[^ ]* ::' >$out
                ''
              }"
          )

      # Test apparmor profile states by using `diff` against `aa-status`
      with subtest("apparmorProfileStates"):
          machine.succeed("${pkgs.diffutils}/bin/diff -u <(${pkgs.apparmor-bin-utils}/bin/aa-status) ${pkgs.writeText "expected.states" ''
            apparmor module is loaded.
            2 profiles are loaded.
            1 profiles are in enforce mode.
               hello
            1 profiles are in complain mode.
               sl
            0 profiles are in prompt mode.
            0 profiles are in kill mode.
            0 profiles are in unconfined mode.
            0 processes have profiles defined.
            0 processes are in enforce mode.
            0 processes are in complain mode.
            0 processes are in prompt mode.
            0 processes are in kill mode.
            0 processes are unconfined but have a profile defined.
            0 processes are in mixed mode.
          ''}")

      # Test apparmor profile files in /etc/apparmor.d/<name> to be either a correct symlink (sl) or have the right file contents (hello)
      with subtest("apparmorProfileTargets"):
          machine.succeed("${pkgs.diffutils}/bin/diff -u <(${pkgs.file}/bin/file /etc/static/apparmor.d/sl) ${pkgs.writeText "expected.link" ''
            /etc/static/apparmor.d/sl: symbolic link to ${./sl_profile}
          ''}")
          machine.succeed("${pkgs.diffutils}/bin/diff -u /etc/static/apparmor.d/hello ${pkgs.writeText "expected.content" helloProfileContents}")
    '';
  }
)
