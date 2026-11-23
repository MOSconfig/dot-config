# Firefox

English | [简体中文](Firefox-zh-CN.md)

`uu --firefox` or `./install.sh --firefox` configures every Firefox install's default profile on this Mac. It manages two things: a small `user.js` and the oh-my-firefox theme. A plain `uu` or `./install.sh` leaves Firefox alone and prints one line saying it was skipped. Profiles already set up keep their `user.js` link, so a pref change committed here still reaches Firefox at its next start.

## Profiles

The installer reads `~/Library/Application Support/Firefox/profiles.ini` and uses the `Default=` profile of each `[Install…]` section, one per installed Firefox edition. Profiles that no install uses are left alone. A path outside the Firefox folder is ignored.

## `user.js`

`config/firefox/user.js` links into each of those profiles as `user.js`. Its manifest row uses the `firefox` type; the destination is relative to each profile, not to `$HOME`.

Firefox reads `user.js` at every start and applies it over `about:config`. The managed prefs are:

| Prefs | Value |
|---|---|
| `toolkit.legacyUserProfileCustomizations.stylesheets` | `true`; required by the theme |
| `browser.search.suggest.enabled`, `browser.urlbar.suggest.*` | `false`; no search, trending, sponsored, or top-site suggestions |
| `browser.newtabpage.*` | `false`; no new-tab page, stories, or top sites |

To change one of these, edit `config/firefox/user.js`; a change in `about:config` is reset at the next start. Other prefs, such as pinned sites, stay yours in `about:config` and are never stored in this public repo.

## Default fonts

`user.js` sets no font, so pages use Firefox's own default fonts. The oh-my-firefox theme still styles Firefox's own UI, view-source, and DevTools.

Older versions of `user.js` set Rec fonts and their sizes. Firefox keeps those values in the profile after the lines leave `user.js`, and install never edits a profile's `prefs.js`. To reset them once per profile:

1. Open `about:config` and search for `font.`.
2. Click the reset arrow on each changed (bold) entry, such as `font.name.sans-serif.x-western` or `font.size.variable.x-western`.
3. Search for `privacy.fingerprintingProtection.overrides` and reset it too.

Pages then fall back to Firefox's defaults. A font you set later stays yours.

## oh-my-firefox theme

The profile's `chrome/` folder is the separate public repo [MOSconfig/oh-my-firefox](https://github.com/MOSconfig/oh-my-firefox), with `userChrome.css` and `userContent.css`. dot-configs does not copy it.

For each profile, the installer:

- clones it into `chrome/` when `chrome/` is missing;
- fast-forwards it when `chrome/` is a clean checkout of oh-my-firefox on a branch with an upstream;
- leaves it alone, with a message, when `chrome/` is not a Git checkout, tracks another repo, or has local changes, local commits, or a detached HEAD.

Git never prompts and never merges or forces. Set `DOT_CONFIGS_OH_MY_FIREFOX_URL` to clone from another URL. Edit the theme in its own repo.

## Apply

Restart Firefox after `uu --firefox` or `./install.sh --firefox`. Firefox reads `user.js` and `chrome/` only at start.

## Check

```sh
scripts/check.sh firefox
ls -l "$HOME/Library/Application Support/Firefox/Profiles"/*/user.js
git -C "$HOME/Library/Application Support/Firefox/Profiles/<profile>/chrome" status -sb
```
