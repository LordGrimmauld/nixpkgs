{ lib, ... }:
{
  name = "restrict-suid-sgid";
  meta.maintainers = with lib.maintainers; [ grimmauld ];

  nodes.machine =
    { pkgs, ... }:
    {
      security.restrict-suid-sgid.enable = true;

      systemd.package = pkgs.systemd.overrideAttrs (old: {
        patches = old.patches or [ ] ++ [
          ../../pkgs/os-specific/linux/systemd/default-restrict-suid-sgid.patch
        ];
      });
    };
  testScript = ''
    import json
    allowed: list[str] = ["suid-sgid-wrappers.service", "systemd-tmpfiles-resetup.service", "systemd-tmpfiles-setup.service" ]
    machine.wait_for_unit("default.target")

    failed = machine.succeed("systemctl --failed -o json")
    assert json.loads(failed) == []

    output = machine.succeed("systemctl list-units -o json -t service --no-pager --all")
    for unit in json.loads(output):
      if unit["load"] != "loaded":
        continue
      with subtest(unit["unit"]):
        security_json = machine.succeed(f"systemd-analyze security {unit["unit"]} --json=short --no-pager")
        for property in json.loads(security_json):
          if property["name"] == "RestrictSUIDSGID=":
            print("found prop")
            assert (not property["set"]) if unit["unit"] in allowed else property["set"]
  '';
}
