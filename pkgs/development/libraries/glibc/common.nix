/* Build configuration used to build glibc, Info files, and locale
   information.

   Note that this derivation has multiple outputs and does not respect the
   standard convention of putting the executables into the first output. The
   first output is `lib` so that the libraries provided by this derivation
   can be accessed directly, e.g.

     "${pkgs.glibc}/lib/ld-linux-x86_64.so.2"

   The executables are put into `bin` output and need to be referenced via
   the `bin` attribute of the main package, e.g.

     "${pkgs.glibc.bin}/bin/ldd".

  The executables provided by glibc typically include `ldd`, `locale`, `iconv`
  but the exact set depends on the library version and the configuration.
*/

# Note: this package is used for bootstrapping fetchurl, and thus
# cannot use fetchpatch! All mutable patches (generated by GitHub or
# cgit) that are needed here should be included directly in Nixpkgs as
# files.

{ stdenv, lib
, buildPackages
, fetchurl
, linuxHeaders ? null
, gd ? null, libpng ? null
, libidn2
, bison
, python3Minimal
}:

{ pname
, withLinuxHeaders ? false
, profilingLibraries ? false
, withGd ? false
, withLibcrypt ? false
, extraBuildInputs ? []
, extraNativeBuildInputs ? []
, ...
} @ args:

let
  version = "2.35";
  patchSuffix = "-224";
  sha256 = "sha256-USNzL2tnzNMZMF79OZlx1YWSEivMKmUYob0lEN0M9S4=";
in

assert withLinuxHeaders -> linuxHeaders != null;
assert withGd -> gd != null && libpng != null;

stdenv.mkDerivation ({
  version = version + patchSuffix;

  enableParallelBuilding = true;

  patches =
    [
      /* No tarballs for stable upstream branch, only https://sourceware.org/git/glibc.git and using git would complicate bootstrapping.
          $ git fetch --all -p && git checkout origin/release/2.35/master && git describe
          glibc-2.35-210-ge123f08ad5
          $ git show --minimal --reverse glibc-2.35.. | gzip -9n --rsyncable - > 2.35-master.patch.gz

         To compare the archive contents zdiff can be used.
          $ zdiff -u 2.35-master.patch.gz ../nixpkgs/pkgs/development/libraries/glibc/2.35-master.patch.gz
       */
      ./2.35-master.patch.gz

      /* Allow NixOS and Nix to handle the locale-archive. */
      ./nix-locale-archive.patch

      /* Don't use /etc/ld.so.cache, for non-NixOS systems.  */
      ./dont-use-system-ld-so-cache.patch

      /* Don't use /etc/ld.so.preload, but /etc/ld-nix.so.preload.  */
      ./dont-use-system-ld-so-preload.patch

      /* The command "getconf CS_PATH" returns the default search path
         "/bin:/usr/bin", which is inappropriate on NixOS machines. This
         patch extends the search path by "/run/current-system/sw/bin". */
      ./fix_path_attribute_in_getconf.patch

      ./fix-x64-abi.patch

      /* https://github.com/NixOS/nixpkgs/pull/137601 */
      ./nix-nss-open-files.patch

      ./0001-Revert-Remove-all-usage-of-BASH-or-BASH-in-installed.patch
    ]
    ++ lib.optional stdenv.hostPlatform.isMusl ./fix-rpc-types-musl-conflicts.patch
    ++ lib.optional stdenv.buildPlatform.isDarwin ./darwin-cross-build.patch;

  postPatch =
    ''
      # Needed for glibc to build with the gnumake 3.82
      # http://comments.gmane.org/gmane.linux.lfs.support/31227
      sed -i 's/ot \$/ot:\n\ttouch $@\n$/' manual/Makefile

      # nscd needs libgcc, and we don't want it dynamically linked
      # because we don't want it to depend on bootstrap-tools libs.
      echo "LDFLAGS-nscd += -static-libgcc" >> nscd/Makefile

      # Ensure that `__nss_files_fopen` can still be wrapped by `libredirect`.
      sed -i -e '/libc_hidden_def (__nss_files_fopen)/d' nss/nss_files_fopen.c
      sed -i -e '/libc_hidden_proto (__nss_files_fopen)/d' include/nss_files.h
    ''
    # FIXME: find a solution for infinite recursion in cross builds.
    # For now it's hopefully acceptable that IDN from libc doesn't reliably work.
    + lib.optionalString (stdenv.hostPlatform == stdenv.buildPlatform) ''

      # Ensure that libidn2 is found.
      patch -p 1 <<EOF
      --- a/inet/idna.c
      +++ b/inet/idna.c
      @@ -25,1 +25,1 @@
      -#define LIBIDN2_SONAME "libidn2.so.0"
      +#define LIBIDN2_SONAME "${lib.getLib libidn2}/lib/libidn2.so.0"
      EOF
    '';

  configureFlags =
    [ "-C"
      "--enable-add-ons"
      "--sysconfdir=/etc"
      "--enable-stack-protector=strong"
      "--enable-bind-now"
      (lib.withFeatureAs withLinuxHeaders "headers" "${linuxHeaders}/include")
      (lib.enableFeature profilingLibraries "profile")
    ] ++ lib.optionals (stdenv.hostPlatform.isx86 || stdenv.hostPlatform.isAarch64) [
      # This feature is currently supported on
      # i386, x86_64 and x32 with binutils 2.29 or later,
      # and on aarch64 with binutils 2.30 or later.
      # https://sourceware.org/glibc/wiki/PortStatus
      "--enable-static-pie"
    ] ++ lib.optionals stdenv.hostPlatform.isx86 [
      # Enable Intel Control-flow Enforcement Technology (CET) support
      "--enable-cet"
    ] ++ lib.optionals withLinuxHeaders [
      "--enable-kernel=3.10.0" # RHEL 7 and derivatives, seems oldest still supported kernel
    ] ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      (lib.flip lib.withFeature "fp"
         (stdenv.hostPlatform.gcc.float or (stdenv.hostPlatform.parsed.abi.float or "hard") == "soft"))
      "--with-__thread"
    ] ++ lib.optionals (stdenv.hostPlatform == stdenv.buildPlatform && stdenv.hostPlatform.isAarch32) [
      "--host=arm-linux-gnueabi"
      "--build=arm-linux-gnueabi"

      # To avoid linking with -lgcc_s (dynamic link)
      # so the glibc does not depend on its compiler store path
      "libc_cv_as_needed=no"
    ]
    ++ lib.optional withGd "--with-gd"
    ++ lib.optional (!withLibcrypt) "--disable-crypt";

  makeFlags = [
    "OBJCOPY=${stdenv.cc.targetPrefix}objcopy"
  ];

  installFlags = [ "sysconfdir=$(out)/etc" ];

  # out as the first output is an exception exclusive to glibc
  outputs = [ "out" "bin" "dev" "static" ];

  strictDeps = true;
  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = [ bison python3Minimal ] ++ extraNativeBuildInputs;
  buildInputs = [ linuxHeaders ] ++ lib.optionals withGd [ gd libpng ] ++ extraBuildInputs;

  env = {
    linuxHeaders = lib.optionalString withLinuxHeaders linuxHeaders;
    inherit (stdenv) is64bit;
    # Needed to install share/zoneinfo/zone.tab.  Set to impure /bin/sh to
    # prevent a retained dependency on the bootstrap tools in the stdenv-linux
    # bootstrap.
    BASH_SHELL = "/bin/sh";
  };

  # Used by libgcc, elf-header, and others to determine ABI
  passthru = { inherit version; minorRelease = version; };
}

// (removeAttrs args [ "withLinuxHeaders" "withGd" ]) //

{
  src = fetchurl {
    url = "mirror://gnu/glibc/glibc-${version}.tar.xz";
    inherit sha256;
  };

  # Remove absolute paths from `configure' & co.; build out-of-tree.
  preConfigure = ''
    export PWD_P=$(type -tP pwd)
    for i in configure io/ftwtest-sh; do
        # Can't use substituteInPlace here because replace hasn't been
        # built yet in the bootstrap.
        sed -i "$i" -e "s^/bin/pwd^$PWD_P^g"
    done

    mkdir ../build
    cd ../build

    configureScript="`pwd`/../$sourceRoot/configure"

    ${lib.optionalString (stdenv.cc.libc != null)
      ''makeFlags="$makeFlags BUILD_LDFLAGS=-Wl,-rpath,${stdenv.cc.libc}/lib OBJDUMP=${stdenv.cc.bintools.bintools}/bin/objdump"''
    }


  '' + lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) ''
    sed -i s/-lgcc_eh//g "../$sourceRoot/Makeconfig"

    cat > config.cache << "EOF"
    libc_cv_forced_unwind=yes
    libc_cv_c_cleanup=yes
    libc_cv_gnu89_inline=yes
    EOF

    # ./configure has logic like
    #
    #     AR=`$CC -print-prog-name=ar`
    #
    # This searches various directories in the gcc and its wrapper. In nixpkgs,
    # this returns the bare string "ar", which is build ar. This can result as
    # a build failure with the following message:
    #
    #     libc_pic.a: error adding symbols: archive has no index; run ranlib to add one
    #
    # (Observed cross compiling from aarch64-linux -> armv7l-linux).
    #
    # Nixpkgs passes a correct value for AR and friends, so to use the correct
    # set of tools, we only need to delete this special handling.
    sed -i \
      -e '/^AR=/d' \
      -e '/^AS=/d' \
      -e '/^LD=/d' \
      -e '/^OBJCOPY=/d' \
      -e '/^OBJDUMP=/d' \
      $configureScript
  '';

  preBuild = lib.optionalString withGd "unset NIX_DONT_SET_RPATH";

  doCheck = false; # fails

  meta = with lib; {
    homepage = "https://www.gnu.org/software/libc/";
    description = "The GNU C Library";

    longDescription =
      '' Any Unix-like operating system needs a C library: the library which
         defines the "system calls" and other basic facilities such as
         open, malloc, printf, exit...

         The GNU C library is used as the C library in the GNU system and
         most systems with the Linux kernel.
      '';

    license = licenses.lgpl2Plus;

    maintainers = with maintainers; [ eelco ma27 ];
    platforms = platforms.linux;
  } // (args.meta or {});
})
