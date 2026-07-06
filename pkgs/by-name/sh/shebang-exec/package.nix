{ writeShellApplication, gawk }:
writeShellApplication {
  runtimeInputs = [
    gawk
  ];
  name = "shebang-exec";
  text = ''
    FILE=$(realpath "$1")
    export FILE

    directive=$(
      awk '
        /^#!/ { last=$0; next }
        /^[[:space:]]*$/ { next }
        { exit }
        END { print last }
      ' "$FILE"
    )

    exec sh -c "''${directive#\#! }"
  '';
}
