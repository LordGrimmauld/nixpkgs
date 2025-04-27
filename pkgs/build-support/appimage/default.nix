{
  lib,
  bash,
  binutils-unwrapped,
  coreutils,
  gawk,
  libarchive,
  pv,
  squashfsTools,
  buildFHSEnv,
  pkgs,
}:

rec {
  appimage-exec = pkgs.replaceVarsWith {
    src = ./appimage-exec.sh;
    isExecutable = true;
    dir = "bin";
    replacements = {
      inherit (pkgs) runtimeShell;
      path = lib.makeBinPath [
        bash
        binutils-unwrapped
        coreutils
        gawk
        libarchive
        pv
        squashfsTools
      ];
    };
  };

  extract =
    args@{
      pname,
      version,
      name ? null,
      postExtract ? "",
      src,
      ...
    }:
    assert lib.assertMsg (
      name == null
    ) "The `name` argument is deprecated. Use `pname` and `version` instead to construct the name.";
    pkgs.runCommand "${pname}-${version}-extracted"
      {
        nativeBuildInputs = [ appimage-exec ];
        strictDeps = true;
      }
      ''
        appimage-exec.sh -x $out ${src}
        ${postExtract}
      '';

  # for compatibility, deprecated
  extractType1 = extract;
  extractType2 = extract;
  wrapType1 = wrapType2;

  wrapAppImage =
    args@{
      src,
      extraPkgs ? pkgs: [ ],
      meta ? { },
      ...
    }:
    buildFHSEnv (
      defaultFhsEnvArgs
      // {
        targetPkgs = pkgs: [ appimage-exec ] ++ defaultFhsEnvArgs.targetPkgs pkgs ++ extraPkgs pkgs;

        runScript = "appimage-exec.sh -w ${src} --";

        meta = {
          sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
        } // meta;
      }
      // (removeAttrs args (builtins.attrNames (builtins.functionArgs wrapAppImage)))
    );

  wrapType2 =
    args@{
      src,
      extraPkgs ? pkgs: [ ],
      ...
    }:
    wrapAppImage (
      args
      // {
        inherit extraPkgs;
        src = extract (
          lib.filterAttrs (
            key: value:
            builtins.elem key [
              "pname"
              "version"
              "src"
            ]
          ) args
        );

        # passthru src to make nix-update work
        # hack to keep the origin position (unsafeGetAttrPos)
        passthru =
          lib.pipe args [
            lib.attrNames
            (lib.remove "src")
            (removeAttrs args)
          ]
          // args.passthru or { };
      }
    );

  defaultFhsEnvArgs = {
    # Most of the packages were taken from the Steam chroot
    targetPkgs =
      pkgs: with pkgs; [
        gtk3
        bashInteractive
        zenity
        xorg.xrandr
        which
        perl
        xdg-utils
        iana-etc
        krb5
        gsettings-desktop-schemas
        hicolor-icon-theme # dont show a gtk warning about hicolor not being installed
      ];

    # list of libraries expected in an appimage environment:
    # https://github.com/AppImage/pkg2appimage/blob/master/excludelist
    multiPkgs =
      pkgs: with pkgs; [
        # ld-linux.so.2
        # ld-linux-x86-64.so.2
        # libanl.so.1
        # libBrokenLocale.so.1
        # libc.so.6#
        # libdl.so.2
        # libm.so.6
        # libmvec.so.1
        # libnsl.so.1
        # libnss_compat.so.2
        # libnss_db.so.2
        # libnss_dns.so.2
        # libnss_files.so.2
        # libnss_hesiod.so.2
        # libpthread.so.0
        # libresolv.so.2
        # librt.so.1
        # libthread_db.so.1
        # libutil.so.1
        glibc.out

        # libcrypt.so.1
        # removed from the upstream list
        # libxcrypt-legacy

        libnss_nis # libnss_nis.so.2

        # libstdc++.so.6
        # libgcc_s.so.1 is seemingly missing from the nixpkgs build
        libgcc

        # libGL.so.1
        # libEGL.so.1
        # libGLdispatch.so.0
        # libGLX.so.0
        # libOpenGL.so.0
        libGL

        libdrm # libdrm.so.2
        libgbm # libgbm.so.1

        # libxcb.so.1
        # libxcb-dri3.so.0
        # libxcb-dri2.so.0
        xorg.libxcb

        # libX11.so.6
        # libX11-xcb.so.1
        xorg.libX11

        # libwayland-client.so.0
        wayland

        # libgio-2.0.so.0
        # libglib-2.0.so.0
        # libgmodule-2.0.so.0
        # libgobject-2.0.so.0
        # libgthread-2.0.so.0
        glib

        # libpangoft2-1.0.so.0
        # libpangocairo-1.0.so.0
        # libpango-1.0.so.0
        # pango has some of its own implicit dependencies that are apparently needed
        pango
        cairo
        libthai

        # libgdk-x11-2.0.so.0
        # libgtk-x11-2.0.so.0
        gtk2

        alsa-lib # libasound.so.2
        gdk-pixbuf # libgdk_pixbuf-2.0.so.0
        fontconfig # libfontconfig.so.1
        freetype # libfreetype.so.6
        harfbuzz # libharfbuzz.so.0
        e2fsprogs # libcom_err.so.2
        expat # libexpat.so.1
        libgpg-error # libgpg-error.so.0

        # libgssapi_krb5.so.2
        # libk5crypto.so.3
        # libkrb5support.so.0
        krb5

        # libheimbase.so.1
        # libhx509.so.5
        # libkrb5.so.26
        # libkrb5.so.3
        # libwind.so.0
        # libgssapi.so.3
        heimdal

        xorg.libICE # libICE.so.6
        keyutils.lib # libkeyutils.so.1
        p11-kit # libp11-kit.so.0
        xorg.libSM # libSM.so.6
        libusb1 # libusb-1.0.so.0

        # libuuid.so.1
        util-linux
        libuuid

        zlib # libz.so.1
        libjack2 # libjack.so.0
        pipewire # libpipewire-0.3.so.0
        nss # libnss3.so
        freeglut # libglut.so.3
        fribidi # libfribidi.so.0
        gmp # libgmp.so.10

        # libidn.so.11
        # libcidn.so.1 missing from our build
        libidn

        # these shared objects don't exist in nixpkgs:
        # libnss_nisplus.so.2
        # libglapi.so.0
        # libhcrypto.so.4
        # libheimntlm.so.0
        # libpcre.so.3
        # libroken.so.18

        # libsasl2.so.2
        cyrus_sasl

        # these make sense but are not listed:
        libgcrypt
        desktop-file-utils
        bzip2
        dbus
        openssl
        curlWithGnuTls
        alsa-lib

        libselinux

        libxkbcommon
        vulkan-loader

        # xorg.libXcomposite
        # xorg.libXtst
        # xorg.libXrandr
        # xorg.libXext
        # xorg.libXfixes
        # libGL

        # gst_all_1.gstreamer
        # gst_all_1.gst-plugins-ugly
        # gst_all_1.gst-plugins-base
        # xorg.xkeyboardconfig
        # xorg.libpciaccess

        # xorg.libXinerama
        # xorg.libXdamage
        # xorg.libXcursor
        # xorg.libXrender
        # xorg.libXScrnSaver
        # xorg.libXxf86vm
        # xorg.libXi
        # xorg.libSM
        # xorg.libICE
        # nspr
        # cups
        libcap
        # SDL2
        # udev
        # dbus-glib
        # atk
        # at-spi2-atk
        # libudev0-shim

        # xorg.libXt
        # xorg.libXmu
        # xorg.xcbutil
        # xorg.xcbutilwm
        # xorg.xcbutilimage
        # xorg.xcbutilkeysyms
        # xorg.xcbutilrenderutil
        # ======================================
        # libGLU
        # libogg
        # libvorbis
        # SDL2_image
        # tbb
        # ======================================

        # flac
        # libglut
        # libjpeg
        # libpng12
        # libpulseaudio
        # libsamplerate
        # libmikmod
        # libtheora
        # libtiff
        # pixman
        # speex
        # SDL2_ttf
        # SDL2_mixer
        # libappindicator-gtk2
        # libcaca
        # libcanberra
        # libvpx
        # librsvg
        # xorg.libXft
        # libvdpau

        # libraries not on the upstream include list, but nevertheless expected
        # by at least one appimage
        libtool.lib # for Synfigstudio
        at-spi2-core
        pciutils # for FreeCAD

        libsecret # For bitwarden
        libmpg123 # Slippi launcher
      ];
  };
}
