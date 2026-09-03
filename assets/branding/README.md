# Sign-in button branding assets

## `google_g_logo.png`

- **Source:** https://developers.google.com/identity/images/g-logo.png
  (Google's official "G" mark, 200 px source).
- **Use:** shipped unmodified as the icon of the branded Google button in
  `lib/ui/account/google_sign_in_button.dart`, under the Sign in with Google
  branding guidelines: https://developers.google.com/identity/branding-guidelines.
  No recoloring, cropping, or restyling; the surrounding button follows the
  guidelines' light-theme rectangular spec (white fill, `#747775` stroke,
  `#1F1F1F` label).
- **Density variants:** none. The button draws the mark at 18 dp and the
  200 px source downsamples cleanly at every device pixel ratio, so no
  `2.0x`/`3.0x` folders are shipped.
