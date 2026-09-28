// Vite's `?raw` suffix imports any file as its literal string content at
// bundle time. The components that read app sources at build time
// (UiLabel's ARB catalog, Screenshot's tool/screenshots/manifest.dart)
// rely on it; without this ambient declaration, `astro check`'s strict
// TypeScript cannot type the imports.
declare module "*?raw" {
  const content: string;
  export default content;
}
