{
  lib,
  stdenv,
  buildGoModule,
  rustPlatform,
  fetchFromGitHub,
  fetchYarnDeps,

  cargo-tauri,
  installShellFiles,
  makeBinaryWrapper,
  nodejs,
  pkg-config,
  yarnConfigHook,

  libayatana-appindicator,
  openssl,
  webkitgtk_4_1,
  jq,
  moreutils,

  testers,
}:

let
  pname = "devpod";
  version = "0.6.15";

  src = fetchFromGitHub {
    owner = "loft-sh";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-fLUJeEwNDyzMYUEYVQL9XGQv/VAxjH4IZ1SJa6jx4Mw=";
  };

  meta = with lib; {
    description = "Codespaces but open-source, client-only and unopinionated: Works with any IDE and lets you use any cloud, kubernetes or just localhost docker";
    mainProgram = "devpod";
    homepage = "https://devpod.sh";
    license = licenses.mpl20;
    maintainers = with maintainers; [ maxbrunet ];
  };
in
rec {
  devpod = buildGoModule {
    inherit
      version
      src
      pname
      meta
      ;

    vendorHash = null;

    env.CGO_ENABLED = 0;

    ldflags = [
      "-X github.com/loft-sh/devpod/pkg/version.version=v${version}"
    ];

    excludedPackages = [ "./e2e" ];

    nativeBuildInputs = [ installShellFiles ];

    postInstall = ''
      $out/bin/devpod completion bash >devpod.bash
      $out/bin/devpod completion fish >devpod.fish
      $out/bin/devpod completion zsh >devpod.zsh
      installShellCompletion devpod.{bash,fish,zsh}
    '';

    passthru.tests.version = testers.testVersion {
      package = devpod;
      command = "devpod version";
      version = "v${version}";
    };
  };

  devpod-desktop = rustPlatform.buildRustPackage {
    inherit version src;
    pname = "devpod-desktop";

    sourceRoot = "${src.name}/desktop";

    offlineCache = fetchYarnDeps {
      yarnLock = "${src}/desktop/yarn.lock";
      hash = "sha256-0Ov+Ik+th2IiuuqJyiO9t8vTyMqxDa9juEwbwHFaoi4=";
    };

    cargoRoot = "src-tauri";
    buildAndTestSubdir = "src-tauri";

    useFetchCargoVendor = true;
    cargoHash = "sha256-BwuV5nAQcTAtdfK4+NKEt8Cj7gqnatRwHh/BYJJrIPo=";

    postPatch =
      ''
        ln -s ${lib.getExe devpod} src-tauri/bin/devpod-cli-${stdenv.hostPlatform.rust.rustcTarget}

        # disable the button that symlinks the `devpod-cli` binary to ~/.local/bin/devpod
        # we'll symlink it manually later to $out/bin/devpod
        substituteInPlace src/components/useInstallCLI.tsx --replace-fail \
          'isDisabled={status === "success"}>' \
          'isDisabled={true}>'

        # don't show popup where it prompts you to press the above mentioned button
        substituteInPlace src/client/client.ts --replace-fail \
          'public async isCLIInstalled(): Promise<Result<boolean>> {' \
          'public async isCLIInstalled(): Promise<Result<boolean>> { return Return.Value(true);'

        # disable upstream updater
        jq \
          '.plugins.updater.endpoints = [ ]
          | .bundle.createUpdaterArtifacts = false' \
          src-tauri/tauri.conf.json \
          | sponge src-tauri/tauri.conf.json
      ''
      + lib.optionalString stdenv.hostPlatform.isLinux ''
        substituteInPlace $cargoDepsCopy/libappindicator-sys-*/src/lib.rs \
          --replace-fail "libayatana-appindicator3.so.1" "${libayatana-appindicator}/lib/libayatana-appindicator3.so.1"
      '';

    nativeBuildInputs =
      [
        jq
        moreutils
        yarnConfigHook
        nodejs
        pkg-config
        cargo-tauri.hook
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [
        makeBinaryWrapper
      ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      libayatana-appindicator
      openssl
      webkitgtk_4_1
    ];

    postInstall =
      lib.optionalString stdenv.hostPlatform.isDarwin ''
        # replace sidecar binary with symlink
        ln -sf ${lib.getExe devpod} "$out/Applications/DevPod.app/Contents/MacOS/devpod-cli"

        makeWrapper "$out"/Applications/DevPod.app/Contents/MacOS/DevPod "$out/bin/dev-pod"
      ''
      + lib.optionalString stdenv.hostPlatform.isLinux ''
        # replace sidecar binary with symlink
        ln -sf ${lib.getExe devpod} "$out/bin/devpod-cli"
      ''
      + ''
        # propagate the `devpod` command
        ln -s ${lib.getExe devpod} "$out/bin/devpod"
      '';

    meta = meta // {
      mainProgram = "dev-pod";
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  };
}
