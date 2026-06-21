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
          # 36 for the app (pinned in app/build.gradle.kts); 35 for Flutter
          # plugin subprojects (file_picker etc.) that default to AGP 8.11's
          # build-tools 35.0.0 and don't expose an override.
          build-tools-36-0-0
          build-tools-35-0-0
          platform-tools
          platforms-android-36
          platforms-android-35
          emulator
          system-images-android-34-google-apis-x86-64
          # Pre-install the NDK pinned in app/build.gradle.kts. AGP can't
          # auto-install into the read-only /nix/store SDK dir.
          ndk-28-2-13676358
        ]);

        # The host's nix post-build hook normally chmods ELF binaries that
        # ship without execute bits (notably flutter_tester), but it only
        # fires on freshly substituted/built paths. If an unprivileged dev
        # user lands on an orphan flutter store path that bypassed the hook,
        # `flutter test` breaks and they can't repair the path themselves.
        # This override forces a fresh build hash, which guarantees the fix.
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
          # glib's .pc declares `Requires.private: sysprof-capture-4`, whose .pc
          # lives in this separate package (not in `sysprof` itself). Without
          # it, pkg-config warns every time it processes glib.
          libsysprof-capture
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
          buildInputs = with pkgs; [
            # Flutter & Dart
            flutter
            dart

            # Android SDK
            androidSdk
            jdk17

            # Linux desktop build deps
          ] ++ linuxBuildDeps ++ [
            # Testing & dev tools
            lcov  # coverage reports
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
