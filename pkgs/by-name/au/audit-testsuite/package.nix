{
  lib,
  stdenv,
  fetchFromGitHub,
  unstableGitUpdater,
  audit,
  liburing,
  nmap,
  psmisc,
  glibc,
  perlPackages,
  makeWrapper,
  iptables,
  coreutils,
  writeShellApplication,
  systemd,
  iproute2,
  inetutils,
}:
let
  perlEnv =
    with perlPackages;
    makeFullPerlPath [
      FileWhich
      TestMockTimeHiRes
      SocketNetlink
    ];
  testEnv = lib.makeBinPath [
    iptables
    iproute2 # ip
    inetutils # ping6
  ];
in

stdenv.mkDerivation (finalAttrs: {
  pname = "audit-testsuite";
  version = "0-unstable-2025-06-24";

  src = fetchFromGitHub {
    owner = "linux-audit";
    repo = "audit-testsuite";
    rev = "5a10451642ac1ba2fa4b31c06a21cf9aa2d38b66";
    hash = "sha256-xpYTvGBmSaC//o5q2PM2ZHiAAOcujEtdWK4LwiA3R54=";
  };

  # syscall_socketcall: 32-bit tests are pain to build
  # filter_exclude: relies on SELinux being enabled (`id -Z`)
  postPatch = ''
    substituteInPlace tests/Makefile \
      --replace-fail "syscall_socketcall" "" \
      --replace-fail "filter_exclude" ""
  '';

  passthru.updateScript = unstableGitUpdater { };

  buildInputs = [
    perlPackages.perl
    liburing
    audit
    nmap
    psmisc
    glibc
  ];

  nativeBuildInputs = [
    makeWrapper
  ];

  doCheck = false; # Can't run checks in the build sandbox, these checks are meant to run in a full VM

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    pushd tests
    find . -type f -executable -exec install -Dm755 "{}" $out/"{}" \;
    popd

    rm -rf $out/filter_exclude
    rm -rf $out/syscall_socketcall

    runHook postInstall
  '';

  fixupPhase = ''
    patchShebangs $out/runtests.pl
    wrapProgram $out/runtests.pl \
      --set PERL5LIB ${perlEnv} \
      --set MODE 64 \
      --set ATS_DEBUG 1 \
      --set DISTRO nixos \
      --set TESTS "$(find $out -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort | paste -sd' ')" \
      --prefix PATH : ${testEnv}
  '';

  passthru.runner = writeShellApplication {
    name = "audit-testsuite-runner";
    runtimeInputs = [
      coreutils
      systemd
    ];
    text = ''
      exec &> >(tee >(systemd-cat -t audit-testsuite))
      testdir=$(mktemp -d)
      export testdir
      cp -r ${finalAttrs.finalPackage}/* "$testdir"
      cd "$testdir"
      chmod +w -R .

      # exec_name test expects coreutils to be actual binaries in an absolute real path,
      # no symlinks to /nix/store/<hash>-coreutils/bin/coreutils
      # fix: copy coreutils to a temporary path where the actual binary can exist under that name
      # https://github.com/linux-audit/audit-testsuite/blob/5a10451642ac1ba2fa4b31c06a21cf9aa2d38b66/tests/exec_name/test#L28-L47
      mkdir coreutils
      for util in id echo ls ; do
        cp "$(realpath "$(which "$util")")" coreutils/"$util"
      done
      sed -iE "s@/usr/bin/@$(pwd)/coreutils/@g" exec_name/test

      exec ./runtests.pl
    '';
  };

  meta = {
    description = "A simple, self-contained regression test suite for the Linux Kernel's audit subsystem";
    homepage = "https://github.com/linux-audit/audit-testsuite";
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [ grimmauld ];
    mainProgram = "audit-testsuite";
    platforms = lib.platforms.all;
  };
})
