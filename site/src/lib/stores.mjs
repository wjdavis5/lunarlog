// Whether lunarlog can be installed from the App Store and Google Play.
//
// The site tells a reader how to get the app. Until both listings are
// public, "install it from the App Store or Google Play" sends them to
// search two stores that do not have it. So the pages that say how to
// install read this one switch, and say what is true either way.
//
// It is a constant, not something the deploy looks up: a listing going
// public is a release the owner makes on purpose (issue #1100 tracks the
// store-console steps), and this is flipped in the same change that adds
// the store links.
//
// Checked false on 5 October 2026: Apple's public lookup
// (itunes.apple.com/lookup?bundleId=com.wjdavis5.lunarlog) returned no
// result, and play.google.com/store/apps/details?id=com.wjdavis5.lunarlog
// returned 404.

/** True once BOTH store listings are public. */
export const STORE_LISTINGS_LIVE = false;

/** What the getting-started guide says about installing on a phone. */
export const PHONE_INSTALL_SENTENCE = STORE_LISTINGS_LIVE
  ? "On a phone, install lunarlog from the App Store or Google Play."
  : "On a phone, lunarlog will install from the App Store and Google Play. Neither listing is open yet.";
