# Capstand design

A native menu bar utility whose main surface is a live video feed, so most of the house style lands on the small surfaces around it.

- **Archetype:** Gallery. The phone screen is the exhibit, with no chrome: no title bar, no buttons, and a draggable body.
- **Themes:** the About panel and menus use system semantic colours. Appearance is set from the menu (System / Light / Dark) through `NSApp.appearance`.
- **Type:** Bricolage Grotesque Bold for the About title. The version string uses the monospaced system font.
- **Radius language:** continuous corners at 14% of the short edge ("Rounded Corners"), matching the iPhone display. Square when the frame style is None.
- **Accent:** near-monochrome. The system accent colour appears only on the About icon.
- **Motion signature:** fade. Windows fade in on plug-in and out on unplug or hide, the About panel fades in, and the window animates when the phone rotates.
- **FintonLabs credit:** "About Capstand" in every menu, including the window's right-click menu, opens a panel with a "Made by FintonLabs" button that links to fintonlabs.com. Escape closes it.
