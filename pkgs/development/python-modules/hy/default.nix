{ lib
, astor
, buildPythonPackage
, colorama
, fetchFromGitHub
, funcparserlib
, hy
, pytestCheckHook
, python
, pythonOlder
, rply
, testers
, toPythonApplication
, hyDefinedPythonPackages ? python-packages: [ ] /* Packages like with python.withPackages */
}:

buildPythonPackage rec {
  pname = "hy";
  version = "0.24.0";
  format = "setuptools";

  disabled = pythonOlder "3.7";

  src = fetchFromGitHub {
    owner = "hylang";
    repo = pname;
    rev = version;
    sha256 = "sha256-PmnYOniYqNHGTxpWuAc+zBhOsgRgMMbERHq81KpHheg=";
  };

  # https://github.com/hylang/hy/blob/1.0a4/get_version.py#L9-L10
  HY_VERSION = version;

  propagatedBuildInputs = [
    colorama
    funcparserlib
  ] ++
  lib.optionals (pythonOlder "3.9") [
    astor
  ] ++
  # for backwards compatibility with removed pkgs/development/interpreters/hy
  # See: https://github.com/NixOS/nixpkgs/issues/171428
  (hyDefinedPythonPackages python.pkgs);

  checkInputs = [
    pytestCheckHook
  ];

  preCheck = ''
    # For test_bin_hy
    export PATH="$out/bin:$PATH"
  '';

  disabledTests = [
    "test_circular_macro_require"
    "test_macro_require"
  ];

  pythonImportsCheck = [ "hy" ];

  passthru = {
    tests.version = testers.testVersion {
      package = hy;
      command = "hy -v";
    };
    # also for backwards compatibility with removed pkgs/development/interpreters/hy
    withPackages = python-packages: (toPythonApplication hy).override {
      hyDefinedPythonPackages = python-packages;
    };
  };

  meta = with lib; {
    description = "A LISP dialect embedded in Python";
    homepage = "https://hylang.org/";
    changelog = "https://github.com/hylang/hy/releases/tag/${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ fab mazurel nixy thiagokokada ];
  };
}
