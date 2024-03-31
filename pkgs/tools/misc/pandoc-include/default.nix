{ buildPythonApplication
, fetchFromGitHub
, lib
, natsort
, panflute
, lxml
, setuptools
, nix-update-script
}:

buildPythonApplication rec {
  pname = "pandoc-include";
  version = "1.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "DCsunset";
    repo = "pandoc-include";
    rev = "refs/tags/v${version}";
    hash = "sha256-aqewWSPxl3BpUIise/rPgBQPsyCOxU6gBlzT1u2mHY0=";
  };

  nativeBuildInputs = [
    setuptools
  ];

  passthru.updateScript = nix-update-script {};

  propagatedBuildInputs = [ natsort panflute lxml ];

  pythonImportsCheck = [ "pandoc_include.main" ];

  meta = with lib; {
    description = "Pandoc filter to allow file and header includes";
    homepage = "https://github.com/DCsunset/pandoc-include";
    license = licenses.mit;
    maintainers = with maintainers; [ ppenguin DCsunset ];
    mainProgram = "pandoc-include";
  };
}
