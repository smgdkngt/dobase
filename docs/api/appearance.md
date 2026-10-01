# Appearance

The colours someone sees Dobase in. Without a theme the app keeps its own look,
light or dark with the system. The built-in themes are the ones
[Omarchy](https://omarchy.org) ships; a theme can also be a palette of your own.

## Show the theme

`GET /appearance`

```json
{
  "name": "tokyo-night",
  "label": "Tokyo Night",
  "mode": "dark",
  "custom": false,
  "colors": { "background": "#1a1b26", "foreground": "#a9b1d6", "accent": "#7aa2f7", "red": "#f7768e" },
  "version": "tokyo-night-5b0c2a91",
  "style": "color-scheme: dark; --color-background: #1a1b26; …",
  "chrome_color": "#13141c",
  "themes": [
    { "name": "catppuccin", "label": "Catppuccin", "mode": "dark" },
    { "name": "catppuccin-latte", "label": "Catppuccin Latte", "mode": "light" }
  ]
}
```

- `name`, `label` and `mode` are `null` on the app's own look.
- `custom` says the colours are your own rather than a built-in theme's.
- `colors` is the palette the theme is made from (`null` on the app's own
  look), for a client that draws itself.
- `themes` lists the built-in themes.
- `version`, `style` and `chrome_color` are what the web app puts on the page:
  the design tokens worked out from the palette, and the colour for the
  browser's own chrome.

A read token is enough.

## Pick a theme

`PATCH /appearance` with the name of a built-in theme:

```json
{ "theme": "gruvbox" }
```

`{ "theme": null }` goes back to the app's own look.

To bring a palette of your own, send its colours along. The names are the ones
Omarchy's `colors.toml` uses, and every value is a six-digit hex colour:

```json
{
  "theme": "my-desktop",
  "colors": {
    "mode": "dark",
    "background": "#1a1b26",
    "dark_background": "#13141c",
    "foreground": "#a9b1d6",
    "bright_foreground": "#c0caf5",
    "accent": "#7aa2f7",
    "red": "#f7768e",
    "yellow": "#e0af68",
    "orange": "#eb927b",
    "green": "#9ece6a",
    "cyan": "#449dab",
    "blue": "#7aa2f7",
    "magenta": "#ad8ee6"
  }
}
```

- `background`, `foreground` and `accent` are required. The rest fall back to
  something derived from those, or to the app's own status colours.
- `mode` is `light` or `dark`; without it the background decides.
- Other keys are ignored. Text, the accent and buttons are adjusted where
  needed so they stay readable (WCAG AA) on the palette's background.
- A palette that is the same as the built-in theme of that name is stored as
  the built-in theme.

Both answer with the theme as above. Every page the person has open takes the
new colours at once.

An unknown name without colours, or colours that don't make a palette, is a
`422`:

```json
{ "error": "Unknown theme. Pick one of the built-in themes, or send its colors." }
```

## Following an Omarchy desktop

`dobase theme sync` sends the palette of the theme an Omarchy desktop is on, and
`dobase theme follow` installs a `theme-set` hook that does so on every switch.
See the [CLI](../../cli/README.md#themes).
