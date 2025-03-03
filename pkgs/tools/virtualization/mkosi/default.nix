{ lib
, fetchFromGitHub
, fetchpatch
, stdenv
, python3
, bubblewrap
, systemd
, pandoc

  # Python packages
, setuptools
, setuptools-scm
, wheel
, buildPythonApplication
, pytestCheckHook
, pefile

  # Optional dependencies
, withQemu ? false
, qemu
, OVMF
}:
let
  # For systemd features used by mkosi, see
  # https://github.com/systemd/mkosi/blob/19bb5e274d9a9c23891905c4bcbb8f68955a701d/action.yaml#L64-L72
  systemdForMkosi = (systemd.overrideAttrs (oldAttrs: {
    patches = oldAttrs.patches ++ [
      # Enable setting a deterministic verity seed for systemd-repart. Remove when upgrading to systemd 255.
      (fetchpatch {
        url = "https://github.com/systemd/systemd/commit/81e04781106e3db24e9cf63c1d5fdd8215dc3f42.patch";
        hash = "sha256-KO3poIsvdeepPmXWQXNaJJCPpmBb4sVmO+ur4om9f5k=";
      })
      # repart: make sure rewinddir() is called before readdir() when performing rm -rf. Remove when upgrading to systemd 255.
      (fetchpatch {
        url = "https://github.com/systemd/systemd/commit/6bbb893b90e2dcb05fb310ba4608f9c9dc587845.patch";
        hash = "sha256-A6cF2QAeYHGc0u0V1JMxIcV5shzf5x3Q6K+blZOWSn4=";
      })
    ];
  })).override {
    withRepart = true;
    withBootloader = true;
    withSysusers = true;
    withFirstboot = true;
    withEfi = true;
    withUkify = true;
  };

  python3pefile = python3.withPackages (ps: with ps; [
    pefile
  ]);
in
buildPythonApplication rec {
  pname = "mkosi";
  version = "19";
  format = "pyproject";

  outputs = [ "out" "man" ];

  src = fetchFromGitHub {
    owner = "systemd";
    repo = "mkosi";
    rev = "v${version}";
    hash = "sha256-KjJM+KZCgUnsaEN2ZorhH0AR5nmiV2h3i7Vb3KdGFtI=";
  };

  # Fix ctypes finding library
  # https://github.com/NixOS/nixpkgs/issues/7307
  postPatch = lib.optionalString stdenv.isLinux ''
    substituteInPlace mkosi/run.py \
      --replace 'ctypes.util.find_library("c")' "'${stdenv.cc.libc}/lib/libc.so.6'"
    substituteInPlace mkosi/__init__.py \
      --replace '/usr/lib/systemd/ukify' "${systemdForMkosi}/lib/systemd/ukify"
  '' + lib.optionalString withQemu ''
    substituteInPlace mkosi/qemu.py \
      --replace '/usr/share/ovmf/x64/OVMF_VARS.fd' "${OVMF.variables}" \
      --replace '/usr/share/ovmf/x64/OVMF_CODE.fd' "${OVMF.firmware}"
  '';

  nativeBuildInputs = [
    pandoc
    setuptools
    setuptools-scm
    wheel
  ];

  propagatedBuildInputs = [
    systemdForMkosi
    bubblewrap
  ] ++ lib.optional withQemu [
    qemu
  ];

  postBuild = ''
    ./tools/make-man-page.sh
  '';

  checkInputs = [
    pytestCheckHook
  ];

  pythonImportsCheck = [
    "mkosi"
  ];

  postInstall = ''
    mkdir -p $out/share/man/man1
    mv mkosi/resources/mkosi.1 $out/share/man/man1/
  '';

  makeWrapperArgs = [
    "--set MKOSI_INTERPRETER ${python3pefile}/bin/python3"
    "--prefix PYTHONPATH : \"$PYTHONPATH\""
  ];

  meta = with lib; {
    description = "Build legacy-free OS images";
    homepage = "https://github.com/systemd/mkosi";
    changelog = "https://github.com/systemd/mkosi/releases/tag/v${version}";
    license = licenses.lgpl21Only;
    mainProgram = "mkosi";
    maintainers = with maintainers; [ malt3 katexochen ];
    platforms = platforms.linux;
  };
}
