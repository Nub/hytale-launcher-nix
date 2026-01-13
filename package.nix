{ pkgs }:

let
  # === AUTO-UPDATE MARKERS - DO NOT MODIFY FORMAT ===
  version = "2025.01.14";
  sha256 = "sha256-iBYZTbm82X+CbF9v/7pwOxxxfK/bwlBValCAVC5xgV8=";
  # === END AUTO-UPDATE MARKERS ===

  pname = "hytale-launcher";
  flatpakUrl = "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak";

  # Unwrapped derivation - extracts and patches the binary
  hytale-launcher-unwrapped = pkgs.stdenv.mkDerivation {
    pname = "${pname}-unwrapped";
    inherit version;

    src = pkgs.fetchurl {
      url = flatpakUrl;
      inherit sha256;
    };

    dontUnpack = true;

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      ostree
    ];

    buildInputs = with pkgs; [
      webkitgtk_4_1
      gtk3
      glib
      gdk-pixbuf
      libsoup_3
      cairo
      pango
      at-spi2-atk
      harfbuzz
      glibc
    ];

    runtimeDependencies = with pkgs; [
      libGL
      libxkbcommon
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
    ];

    buildPhase = ''
      runHook preBuild

      mkdir -p repo
      ostree init --repo=repo --mode=archive
      ostree static-delta apply-offline --repo=repo $src

      COMMIT_FILE=$(find repo/objects -name "*.commit" -type f | head -1)
      COMMIT_DIR=$(dirname "$COMMIT_FILE")
      COMMIT_PREFIX=$(basename "$COMMIT_DIR")
      COMMIT_SUFFIX=$(basename "$COMMIT_FILE" .commit)
      COMMIT_HASH="''${COMMIT_PREFIX}''${COMMIT_SUFFIX}"

      rm -rf checkout
      ostree checkout --repo=repo -U $COMMIT_HASH checkout

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/hytale-launcher
      install -m755 checkout/files/bin/hytale-launcher $out/lib/hytale-launcher/

      # Install icons from flatpak checkout
      for size in 32 48 64 128 256; do
        icon_src="checkout/files/share/icons/hicolor/''${size}x''${size}/apps/com.hypixel.HytaleLauncher.png"
        if [ -f "$icon_src" ]; then
          mkdir -p "$out/share/icons/hicolor/''${size}x''${size}/apps"
          install -Dm644 "$icon_src" "$out/share/icons/hicolor/''${size}x''${size}/apps/hytale-launcher.png"
        fi
      done

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Official launcher for Hytale game (unwrapped)";
      homepage = "https://hytale.com";
      license = licenses.unfree;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      maintainers = [{
        name = "Jacob Pyke";
        email = "github@pyk.ee";
        github = "JPyke3";
        githubId = 13283054;
      }];
      platforms = [ "x86_64-linux" ];
    };
  };

  # FHS-wrapped derivation - allows self-updates to work
  hytale-launcher = pkgs.buildFHSEnv {
    name = "hytale-launcher";
    inherit version;

    targetPkgs = pkgs: with pkgs; [
      # Core dependencies
      hytale-launcher-unwrapped

      # WebKit/GTK stack
      webkitgtk_4_1
      gtk3
      glib
      gdk-pixbuf
      libsoup_3
      cairo
      pango
      at-spi2-atk
      harfbuzz

      # Graphics
      libGL
      libxkbcommon
      mesa
      vulkan-loader

      # X11
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libXcursor
      xorg.libXi
      xorg.libxcb

      # Audio
      alsa-lib
      pipewire
      pulseaudio

      # System
      dbus
      fontconfig
      freetype
      glibc
      nspr
      nss
      systemd
      zlib
    ];

    runScript = pkgs.writeShellScript "hytale-launcher-wrapper" ''
      # Hytale data directory
      LAUNCHER_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/Hytale"
      LAUNCHER_BIN="$LAUNCHER_DIR/hytale-launcher"
      BUNDLED_HASH_FILE="$LAUNCHER_DIR/.bundled_hash"
      BUNDLED_BIN="${hytale-launcher-unwrapped}/lib/hytale-launcher/hytale-launcher"

      mkdir -p "$LAUNCHER_DIR"

      # Compute hash of bundled binary to detect Nix package updates
      BUNDLED_HASH=$(sha256sum "$BUNDLED_BIN" | cut -d" " -f1)

      # Copy bundled binary if needed (new install or Nix package update)
      if [ ! -x "$LAUNCHER_BIN" ] || [ ! -f "$BUNDLED_HASH_FILE" ] || [ "$(cat "$BUNDLED_HASH_FILE")" != "$BUNDLED_HASH" ]; then
        install -m755 "$BUNDLED_BIN" "$LAUNCHER_BIN"
        echo "$BUNDLED_HASH" > "$BUNDLED_HASH_FILE"
      fi

      # Required environment variable from Flatpak metadata
      export WEBKIT_DISABLE_COMPOSITING_MODE=1

      exec "$LAUNCHER_BIN" "$@"
    '';

    extraInstallCommands = ''
      # Install desktop file
      mkdir -p $out/share/applications
      cat > $out/share/applications/hytale-launcher.desktop << EOF
[Desktop Entry]
Name=Hytale Launcher
Comment=Official launcher for Hytale
Exec=$out/bin/hytale-launcher
Icon=hytale-launcher
Terminal=false
Type=Application
Categories=Game;
Keywords=hytale;game;launcher;hypixel;
StartupWMClass=com.hypixel.HytaleLauncher
EOF

      # Symlink icons from unwrapped package
      mkdir -p $out/share/icons
      ln -s ${hytale-launcher-unwrapped}/share/icons/hicolor $out/share/icons/hicolor
    '';

    meta = with pkgs.lib; {
      description = "Official launcher for Hytale game";
      longDescription = ''
        The official launcher for Hytale, developed by Hypixel Studios.
        This package extracts and wraps the launcher from the official
        Flatpak distribution, providing FHS compatibility for self-updates.
      '';
      homepage = "https://hytale.com";
      license = licenses.unfree;
      sourceProvenance = with sourceTypes; [ binaryNativeCode ];
      maintainers = [{
        name = "Jacob Pyke";
        email = "github@pyk.ee";
        github = "JPyke3";
        githubId = 13283054;
      }];
      platforms = [ "x86_64-linux" ];
      mainProgram = "hytale-launcher";
    };
  };

in {
  inherit hytale-launcher hytale-launcher-unwrapped;
}
