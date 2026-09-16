# Capstand design

A native menu bar utility whose main surface is a live video feed, so most of the house style lands on the small surfaces around it.

- **Archetype:** Gallery. The phone screen is the exhibit, with no chrome: no title bar, no buttons, and a draggable body.
- **Themes:** the About panel and menus use system semantic colours. Appearance is set from the menu (System / Light / Dark) through `NSApp.appearance`.
- **Type:** Bricolage Grotesque Bold for the About title. The version string uses the monospaced system font.
- **Radius language:** continuous corners at 14% of the short edge ("Rounded Corners"), matching the iPhone display. Square when the frame style is None.
- **Accent:** near-monochrome. The system accent colour appears only on the About icon.
- **Motion signature:** fade. Windows fade in on plug-in and out on unplug or hide, the About panel fades in, and the window animates when the phone rotates.
- **FintonLabs credit:** "About Capstand" in every menu, including the window's right-click menu, opens a panel with a "Made by FintonLabs" button that links to fintonlabs.com. Escape closes it.

## Website (docs/, GitHub Pages)

The recent siblings used Kiosk (3d-servicemap), Console (ableton-ai), Poster (chordic) and Soft product (emberline), so the site uses an archetype none of them did.

- **Archetype:** Blueprint. A line drawing of the phone with callouts on drafting-grid paper. Annotations use section marks (§1, FIG. 1).
- **Layout:** top bar, a split-screen hero (copy on the left, drawing on the right), then full-width sections under a left-hand label column.
- **Type scale:** moderate, about 1.3. Bricolage runs at `wdth` 85–90 for headings and IBM Plex Mono is used for annotations.
- **Surface:** bordered 1px panels. The only depth is a flat offset "drafting" shadow on the primary actions.
- **Radius language:** 0px everywhere on the chrome. Only the drawn phone is rounded.
- **Accent:** a single cobalt ink, `#1f4fd8` in light and `#7aa2ff` in dark. Everything else is neutral ink.
- **Motion signature:** draw-in stroke. SVG paths use `pathLength="1"` and animate `stroke-dashoffset`, staggered 70ms, as the page loads and as they scroll into view. Text rises in. Hover lifts; press depresses.
- **Ground texture:** a two-scale grid, 24px minor and 120px major.
- **Themes:** the toggle cycles System → Light → Dark. The choice is saved to localStorage and applied before first paint.
- **FintonLabs:** an info button fixed at the bottom right opens a `<dialog>` with "Made by FintonLabs".
- **Release coupling:** `release.sh` rewrites the DMG links and the `.dl-ver` spans on every release.
