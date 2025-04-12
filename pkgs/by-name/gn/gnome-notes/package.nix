{
  stdenv,
  lib,
  meson,
  ninja,
  gettext,
  fetchFromGitLab,
  pkg-config,
  wrapGAppsHook4,
  itstool,
  desktop-file-utils,
  python3,
  glib,
  gtk4,
  evolution-data-server,
  gnome-online-accounts,
  json-glib,
  libuuid,
  curl,
  libhandy,
  libadwaita,
  webkitgtk_6_0,
  gnome,
  adwaita-icon-theme,
  libxml2,
  gsettings-desktop-schemas,
  tinysparql,
}:

stdenv.mkDerivation {
  pname = "gnome-notes";
  version = "40.1-unstable-2025-03-22";

  src = fetchFromGitLab {
    domain = "gitlab.gnome.org";
    rev = "36ffedf40a933df45663e58963285869ec0cdb5a";
    repo = "gnome-notes";
    owner = "GNOME";
    hash = "sha256-G1UmtaDWciwFoFsVzg0hi0tosMPuixYBzdcfDRVVHUY=";
  };
  
  doCheck = true;

  postPatch = ''
    chmod +x build-aux/meson_post_install.py
    patchShebangs build-aux/meson_post_install.py
    substituteInPlace build-aux/meson_post_install.py \
      --replace-fail "gtk-update-icon-cache" "gtk4-update-icon-cache"
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gettext
    itstool
    libxml2
    desktop-file-utils
    python3
    gtk4 # For `gtk-update-icon-cache`
    wrapGAppsHook4
  ];

  buildInputs = [
    glib
    gtk4
    json-glib
    libuuid
    curl
    libadwaita
    libhandy
    webkitgtk_6_0
    tinysparql
    gnome-online-accounts
    gsettings-desktop-schemas
    evolution-data-server
    adwaita-icon-theme
  ];

  mesonFlags = [ "-Dupdate_mimedb=false" ];

  passthru = {
    updateScript = gnome.updateScript {
      packageName = "bijiben";
      attrPath = "gnome-notes";
    };
  };

  meta = with lib; {
    description = "Note editor designed to remain simple to use";
    mainProgram = "bijiben";
    homepage = "https://gitlab.gnome.org/GNOME/gnome-notes";
    license = licenses.gpl3;
    maintainers = teams.gnome.members;
    platforms = platforms.linux;
  };
}
