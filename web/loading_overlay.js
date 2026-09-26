// web/loading_overlay.js
//
// Issue #1091, follow-up: remove the CSS-only loading overlay (`#loading`,
// defined in `web/index.html`) once Flutter has painted its first frame.
// Without this, the overlay is only painted over: it stays in the DOM, so the
// accessibility tree keeps exposing `status: "Loading lunarlog…"` and screen
// readers announce it after the app has booted. See the review on PR #1109.
//
// `script-src 'self'` allows this same-origin file; an inline <script> would
// be blocked. `web/index.html` loads it before `flutter_bootstrap.js`, so the
// listener is registered before the first frame can fire.
(function () {
  'use strict';

  function removeLoadingOverlay() {
    var loading = document.getElementById('loading');
    if (loading && loading.parentNode) {
      loading.parentNode.removeChild(loading);
    }
  }

  window.addEventListener('flutter-first-frame', removeLoadingOverlay, {
    once: true,
  });
})();
