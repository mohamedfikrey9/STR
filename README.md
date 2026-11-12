# Steal The Rule — Godot 4.4.1 Android

A complete **playable 2D prototype**, built without external assets. Includes movement, virtual joystick, 2–4 player multiplayer, scoring, timer, collectible energy, 6 rule cards, stealing, round results and GitHub Actions Android debug APK export.

## What is included
- **Solo practice** for testing without another device.
- **LAN multiplayer (2–4 phones)**: one phone HOSTS, others JOIN BY IP. Use the same Wi-Fi or hotspot.
- **Direct-IP internet multiplayer**: requires a public reachable host and UDP port **24567** forwarded/open. There is **no matchmaking, room-code server, NAT traversal or hosted backend** in this version.
- Rules: REVERSE, SLIPPERY, HOLES, SWAP, SLOW, DOUBLE. Pick up a purple card and press LAW. Approach the current rule owner and press STEAL to steal their active rule.
- 180-second round, +1 per energy, +2 per steal; highest score wins.

## Upload to GitHub
1. Create an empty repository `StealTheRule` (public or private).
2. Upload **the contents of this folder** to repository root, including hidden `.github` folder. **Do not upload the ZIP as a single file.**
3. GitHub → Actions → `Build Android Debug APK` → Run workflow. The workflow also runs on pushes to `main`/`master`.
4. When successful, open the workflow run → Artifacts → `StealTheRule-Debug-APK` → download ZIP → extract `StealTheRule.apk`.
5. Install the APK on an Android phone. Android may warn that the app is from outside Play Store.

## Desktop / Android local development
- Import `project.godot` in **Godot 4.4.1** and press F5.
- Desktop: arrow keys/WASD to move; SPACE activates held law, E steals. Mouse can drag virtual joystick.
- Android: landscape; left joystick, right LAW and STEAL buttons.
- On Android the network host can find its Wi-Fi IP in system network settings. Clients enter that IP in JOIN BY IP (tap IP field, type using keyboard, press Enter). Tap the editable IP field to use the Android on-screen keyboard.

## Important build notes
- `.github/workflows/android.yml` sets up Godot, Android SDK, JDK and exports a **debug APK**.
- `export_presets.cfg` specifies the Android export preset. No release signing keys are stored in the repository.
- The Android workflow has **not been executed or verified in this environment**. If a first build fails, check its Actions logs; Godot/SDK template compatibility may require adjustments.
- Network and gameplay code is an initial implementation, not production-hardened or anti-cheat-certified. No backend, persistent accounts, or app store publication.
- For Android LAN connectivity, check device permissions and firewall settings. Hosting across mobile networks typically requires a relay/dedicated server, not just an IP address.

## Folder structure
```
project.godot
main.tscn
scripts/main.gd
export_presets.cfg
.github/workflows/android.yml
.gitignore
README.md
```
