{
  description = "Expense Tracker - Flutter app dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-36-0-0
          platform-tools
          platforms-android-36
          emulator
          system-images-android-34-google-apis-x86-64
        ]);

        # Flutter with flutter_tester execute permission fixed for NixOS
        flutter = pkgs.flutter.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            find $out -name flutter_tester -type f -exec chmod +x {} \;
          '';
        });

        # Linux desktop build dependencies for Flutter
        linuxBuildDeps = with pkgs; [
          clang
          cmake
          ninja
          pkg-config
          gtk3
          glib
          pcre2
          libepoxy
          xorg.libX11
          libGL
          sysprof
        ];

        # Runtime deps needed by the built Flutter Linux app
        linuxRuntimeDeps = with pkgs; [
          gtk3
          glib
          pcre2
          libepoxy
          xorg.libX11
          libGL
          sysprof
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            # Flutter & Dart (patched for NixOS flutter_tester permissions)
            flutter
            pkgs.dart

            # Android SDK
            androidSdk
            pkgs.jdk17

            # Linux desktop build deps
          ] ++ linuxBuildDeps ++ [
            # Testing & dev tools
            pkgs.lcov  # coverage reports
          ];

          shellHook = ''
            export ANDROID_HOME="${androidSdk}/share/android-sdk"
            export ANDROID_SDK_ROOT="$ANDROID_HOME"
            export JAVA_HOME="${pkgs.jdk17}"
            export CHROME_EXECUTABLE="${pkgs.lib.getExe pkgs.chromium}"

            # Point Flutter to system cache to avoid re-downloading
            export PUB_CACHE="''${PUB_CACHE:-$HOME/.pub-cache}"

            # Ensure Flutter can find Linux build tools
            export CC="${pkgs.clang}/bin/clang"
            export CXX="${pkgs.clang}/bin/clang++"
            export CMAKE_PREFIX_PATH="${pkgs.lib.makeSearchPath "lib/cmake" linuxBuildDeps}"

            # LD_LIBRARY_PATH for runtime
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath linuxRuntimeDeps}:''${LD_LIBRARY_PATH:-}"

          '';
        };

        packages.default = pkgs.flutter.mkFlutterApp {
          pname = "expense-tracker";
          version = "0.1.0";
          src = ./.;

          # Linux desktop build
          targetFlutterPlatform = "linux";
        };
      }
    );
}
