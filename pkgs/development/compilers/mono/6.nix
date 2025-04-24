{
  callPackage,
  fetchurl,
}:

callPackage ./generic.nix (rec {
  version = "6.14.0";
  enableParallelBuilding = true;
  src = fetchurl {
    url = "https://dl.winehq.org/mono/sources/mono/mono-${version}.tar.xz";
    hash = "sha256-bdZLOQD15dX1UBbYnM92NchznLszzbgcHDthYi6R1RA=";
  };
})
