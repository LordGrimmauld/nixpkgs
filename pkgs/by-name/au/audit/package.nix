{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
  bash,
  buildPackages,
  linuxHeaders,
  python3,
  swig,
  pkgsCross,
  libcap_ng,
  installShellFiles,

  # Enabling python support while cross compiling would be possible, but the
  # configure script tries executing python to gather info instead of relying on
  # python3-config exclusively
  enablePython ? stdenv.hostPlatform == stdenv.buildPlatform,
  nix-update-script,
  testers,
  nixosTests,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "audit";
  version = "4.1.1-unstable-2025-08-01";

  src = fetchFromGitHub {
    owner = "linux-audit";
    repo = "audit-userspace";
    rev = "408b4001d4545606a33a25e1cb69088408bba3df";
    hash = "sha256-mXDo/CCQioqgYNKygpJdERlDapHmYFHeeNw3xiD+V38=";
  };

  patches = [
    ./disable-legacy-actions.patch
  ];

  postPatch = ''
    substituteInPlace bindings/swig/src/auditswig.i \
      --replace-fail "/usr/include/linux/audit.h" \
                     "${linuxHeaders}/include/linux/audit.h"
  '';

  # https://github.com/linux-audit/audit-userspace/issues/474
  # building databuf_test fails otherwise, as that uses hidden symbols only available in the static builds
  dontDisableStatic = true;

  outputs = [
    "bin"
    "lib"
    "dev"
    "out"
    "man"
  ];

  strictDeps = true;

  depsBuildBuild = [
    buildPackages.stdenv.cc
  ];

  nativeBuildInputs = [
    autoreconfHook
    installShellFiles
  ]
  ++ lib.optionals enablePython [
    python3
    swig
  ];

  buildInputs = [
    bash
    libcap_ng
  ];

  configureFlags = [
    # z/OS plugin is not useful on Linux, and pulls in an extra openldap
    # dependency otherwise
    "--disable-zos-remote"
    "--disable-legacy-actions"
    "--with-arm"
    "--with-aarch64"
    "--with-io_uring"
    "--runstatedir=/run"
    # capability dropping, currently mostly for plugins as those get spawned as root
    # see auditd-plugins(5)
    "--with-libcap-ng=yes"
    (if enablePython then "--with-python" else "--without-python")
  ];

  postInstall = ''
    installShellCompletion --bash init.d/audit.bash_completion
  '';

  enableParallelBuilding = true;

  passthru = {
    updateScript = nix-update-script { };
    tests = {
      musl = pkgsCross.musl64.audit;
      pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;
      plugins = nixosTests.auditd;
    };
  };

  meta = {
    homepage = "https://people.redhat.com/sgrubb/audit/";
    description = "Audit Library";
    changelog = "https://github.com/linux-audit/audit-userspace/releases/tag/v4.1.1";
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ grimmauld ];
    pkgConfigModules = [
      "audit"
      "auparse"
    ];
    platforms = lib.platforms.linux;
  };
})
