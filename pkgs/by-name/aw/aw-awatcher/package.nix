{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  dbus,
  openssl,
  rust-jemalloc-sys,
  sqlite,
  stdenv,
  darwin,
  wayland,
}:

rustPlatform.buildRustPackage rec {
  pname = "aw-awatcher";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "2e3s";
    repo = "awatcher";
    rev = "refs/tags/v${version}";
    hash = "sha256-G7UH2JcKseGZUA+Ac431cTXUP7rxWxYABfq05/ENjUM=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "aw-client-rust-0.1.0" = "sha256-yliRLPM33GWTPcNBDNuKMOkNOMNfD+TI5nRkh+5YSnw=";
    };
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs =
    [
      dbus
      openssl
      rust-jemalloc-sys
      sqlite
    ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
    ]
    ++ lib.optionals stdenv.isLinux [
      wayland
    ];

  env = {
    OPENSSL_NO_VENDOR = true;
  };

  meta = {
    changelog = "https://github.com/2e3s/awatcher/releases/tag/v${version}";
    description = "Activity and idle watchers with wayland compatibility";
    homepage = "https://github.com/2e3s/awatcher";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ grimmauld ];
    mainProgram = "awatcher";
  };
}
