# Hytale Launcher Nix

Nix flake for the official [Hytale Launcher](https://hytale.com), with automated updates.

## Features

- Extracts the official Hytale Launcher from the Flatpak distribution
- FHS-wrapped to allow the launcher's self-update mechanism to work
- Automated hourly version checks with auto-updating PRs
- Proper desktop integration (icons, .desktop file)

## Installation

### Try it out
```bash
nix run github:JPyke3/hytale-launcher-nix
```

### Install persistently
```bash
nix profile install github:JPyke3/hytale-launcher-nix
```

### In a flake
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hytale-launcher.url = "github:JPyke3/hytale-launcher-nix";
  };

  outputs = { self, nixpkgs, hytale-launcher, ... }: {
    # Use in your configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            hytale-launcher.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

### Home Manager
```nix
{ pkgs, inputs, ... }:
{
  home.packages = [
    inputs.hytale-launcher.packages.${pkgs.system}.default
  ];
}
```

## Packages

| Package | Description |
|---------|-------------|
| `hytale-launcher` (default) | FHS-wrapped launcher with self-update support |
| `hytale-launcher-unwrapped` | Raw extracted binary (no FHS wrapper) |

## How Updates Work

This flake uses hash-based version detection:

1. Every hour, GitHub Actions fetches the latest Flatpak from Hytale's servers
2. If the SHA256 hash differs from the current version, an update is detected
3. A PR is automatically created with the new hash
4. After CI verification passes, the PR auto-merges

Since Hytale doesn't publish version numbers, we use date-based versioning (`YYYY.MM.DD`). Multiple same-day updates get a suffix (e.g., `2025.01.14.2`).

## Manual Update

To check for updates manually:
```bash
./scripts/update-version.sh --check  # Check only
./scripts/update-version.sh          # Check and apply
./scripts/update-version.sh --force  # Force update
```

## License

- **Hytale Launcher binary**: Proprietary (Hypixel Studios)

## Credits

- [Hypixel Studios](https://hypixelstudios.com/) for the Hytale Launcher
- [claude-code-nix](https://github.com/sadjow/claude-code-nix) for the auto-update pattern inspiration
