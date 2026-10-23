# mpv-infused

An [mpv](https://mpv.io) setup for macOS with the comforts of a polished player: Dolby Vision that renders with correct colours, automatic subtitles, "Skip Recap" prompts, a right-click menu, and a window that remembers where you left it.

Everything is plain mpv config and Lua scripts on top of Homebrew's mpv, so `brew upgrade` keeps the player itself current.

## Features

- **Dolby Vision, including Profile 5, with hardware decoding.** Recent mpv already renders Dolby Vision through its `gpu-next` renderer (libplacebo over Vulkan/MoltenVK); this config pins that renderer and adds VideoToolbox hardware decoding, which mpv leaves off by default and which makes 4K HEVC far lighter on battery. Profile 5 files (common in Disney+ `DV` releases) look green/purple in many players; here they render correctly.
- **Automatic subtitles.** English tracks are picked automatically. When a file has none, subtitles are fetched from OpenSubtitles, matched by file hash first, then by title and season/episode. They're saved next to the video as `name.en.srt`, so the next play is instant.
- **Skip Recap / Intro / Credits.** When a chapter with one of those names starts, a prompt appears; press <kbd>Enter</kbd> to jump past it. It uses the chapter markers already embedded in most streaming releases.
- **Right-click menu.** Play/pause, fullscreen, subtitle track picker, **Search Subtitles Online**, audio track, next chapter, float on top.
- **Window memory.** The window never opens larger than 75% of the screen, and reopens at the size and position you last used.
- **Finder integration.** Builds a small `/Applications/mpv.app` launcher, so mpv appears in **Open With** and can be set as the default player.
- **Resilient downloads.** Optional proxy for OpenSubtitles traffic, retries on flaky connections, and a check that rejects anything that isn't really a subtitle file (such as a network block page).

## Requirements

- macOS 11 or later (tested on Apple Silicon)
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/<you>/mpv-infused.git
cd mpv-infused
./install.sh
```

The installer:

1. installs mpv from Homebrew if it isn't already there,
2. backs up an existing `~/.config/mpv` the first time it runs,
3. copies the config and scripts into `~/.config/mpv`,
4. compiles a tiny window-position helper,
5. builds `/Applications/mpv.app` and registers it with Finder (skip with `./install.sh --no-app`).

It's safe to re-run after pulling updates. Your OpenSubtitles settings and saved window position are never overwritten.

To make mpv your default player: right-click a video, then **Get Info → Open with → mpv → Change All…**

### OpenSubtitles

Searching needs a free API key:

1. Sign in at [opensubtitles.com](https://www.opensubtitles.com).
2. Create a consumer at <https://www.opensubtitles.com/en/consumers> and copy its API key.
3. Put it after `api_key=` in `~/.config/mpv/script-opts/opensubtitles.conf`.

Adding your OpenSubtitles `username` and `password` there raises the daily download limit.

If your network blocks OpenSubtitles' download server (the script will say *"download was not a subtitle file"*), you can route its traffic through an HTTP proxy with `proxy=http://user:pass@host:port/`. Set `proxy_page=` to a URL to open automatically when that proxy stops working.

## Controls

| Action | Key / mouse |
| --- | --- |
| Search subtitles online | <kbd>Alt</kbd>+<kbd>O</kbd>, or right-click → **Search Subtitles Online** |
| Skip recap / intro / credits | <kbd>Enter</kbd> while the prompt is showing |
| Context menu | Right-click |
| Seek ±5 seconds | <kbd>←</kbd> / <kbd>→</kbd> |

Everything else is standard mpv.

## Dolby Vision notes

| Profile | Typical source | Support |
| --- | --- | --- |
| 5 | Streaming WEB-DLs (Disney+, Apple TV+, Netflix) | Full: Dolby Vision reshaping applied (tested) |
| 8.1 / 8.4 | Streaming, "DV HDR" releases, iPhone video | Full: Dolby Vision on top of the HDR10/HLG base layer |
| 7 | UHD Blu-ray remuxes | Base layer + Dolby Vision metadata; the enhancement layer is ignored (no visible loss for MEL, minor for FEL) |
| 10 | AV1 Dolby Vision | Supported by the renderer, untested here; AV1 hardware decoding needs Apple M3 or newer |

Dolby Vision **Profile 5** stores video in Dolby's own colour space with no HDR10/SDR fallback. Players that ignore the Dolby Vision metadata show it green and purple. mpv's `gpu-next` renderer applies that metadata itself, and it's the default renderer in recent mpv; older builds default to `vo=gpu`, which doesn't. Apps built on libmpv (such as IINA) draw video their own way and don't get this.

To play such a file in QuickTime instead, you can repackage it as MP4 without re-encoding. Video, Dolby Vision metadata and Atmos audio are copied untouched, and subtitles are converted to MP4 text tracks:

```bash
ffmpeg -i in.mkv -map 0:v -map 0:a -map 0:s -c copy -c:s mov_text -tag:v dvh1 -strict unofficial out.mp4
```

## What's inside

```
config/
  mpv.conf                      renderer, hardware decoding, window size, subtitle language
  input.conf                    key bindings
  scripts/
    opensubtitles.lua           automatic + on-demand subtitle downloads
    skip-chapters.lua           "Skip Recap" prompts from chapter names
    remember-window.lua         saves and restores window size/position
    right-click-menu.lua        context menu
  script-opts/
    opensubtitles.conf.example  settings template (copied to opensubtitles.conf)
    context_menu.conf           menu font size
tools/mpv-winbounds.swift       reads the mpv window's frame (macOS doesn't expose it to mpv)
app/                            mpv.app launcher source, Info.plist, icon renderer
install.sh
```

### Why a launcher app?

Homebrew's mpv is a command-line binary with no `.app`, so Finder can't offer it. The launcher is a tiny compiled program that starts Homebrew's mpv in GUI mode and forwards the files Finder hands it. Because it only points at Homebrew's binary, the player stays up to date with `brew upgrade`.

### Why a helper for the window position?

mpv can't report its own window position on macOS. `mpv-winbounds` asks the window server for it (no special permissions needed), and `remember-window.lua` saves it whenever the window changes.

## Limitations

- The macOS menu bar's menus are built into mpv and can't be extended by scripts, so extra actions live in the right-click menu.
- Without an OpenSubtitles key, only subtitles already inside the file (or `.srt` files next to it) are used.
- A video window opened in fullscreen or minimised isn't saved as the remembered position.

## Uninstall

```bash
rm -rf /Applications/mpv.app
rm -rf ~/.config/mpv          # or restore ~/.config/mpv.backup-* made by the installer
brew uninstall mpv            # optional
```

## License

MIT. mpv itself is licensed separately (GPLv2+/LGPLv2.1+).
