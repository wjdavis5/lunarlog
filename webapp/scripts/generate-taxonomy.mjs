// Build-time taxonomy generator for the React web client (issue #1254).
//
//   node scripts/generate-taxonomy.mjs      (wired into `npm run generate`)
//
// One committed artifact is regenerated from a source that lives outside
// webapp/:
//
//   src/lib/taxonomy/taxonomy.generated.json
//   The day editor's symptom-tag taxonomy, extracted from the app's own
//   `lib/domain/tags.dart` (and `lib/domain/logging/tracking_preferences.dart`
//   for the minor-visibility default) — the same single home for the tag
//   vocabulary the Flutter day sheet renders. Until #1251 compiles
//   `lib/domain` to JavaScript, this generated JSON is how the web client
//   uses the app's taxonomy instead of re-typing it; a freshness test
//   (webapp/test/taxonomy.test.ts) re-runs this builder and fails when the
//   committed artifact drifts, the same discipline `test/messages.test.ts`
//   applies to the message catalogue.
//
// Deterministic: the JSON follows the tags.dart declaration order, so two
// runs on the same input produce byte-identical output.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const webappRoot = resolve(here, '..');
export const repoRoot = resolve(webappRoot, '..');

const tagsPath = join(repoRoot, 'lib', 'domain', 'tags.dart');
export { tagsPath as tagsDartPath };
const trackingPreferencesPath = join(
  repoRoot,
  'lib',
  'domain',
  'logging',
  'tracking_preferences.dart',
);
const careModesPath = join(repoRoot, 'lib', 'domain', 'care_modes.dart');
export const taxonomyJsonOutPath = join(
  webappRoot,
  'src',
  'lib',
  'taxonomy',
  'taxonomy.generated.json',
);

const die = (message) => {
  throw new Error(`generate-taxonomy: ${message}`);
};

/** Extracts the body of the first `const ... <name> ... = { ... };` block. */
function constSetOrMapBody(source, name, file) {
  const start = source.indexOf(`${name} = {`);
  if (start < 0) {
    die(`${file}: no '${name} = {' block found — the extraction parser is stale`);
  }
  const open = source.indexOf('{', start);
  const close = source.indexOf('};', open);
  if (close < 0) {
    die(`${file}: '${name}' block has no closing '};'`);
  }
  return source.slice(open + 1, close);
}

/** The Dart enum declaration order is the categories' default surfacing order. */
function extractCategoryOrder(source) {
  const block = source.indexOf('enum TagCategory {');
  if (block < 0) die('tags.dart: no `enum TagCategory {` declaration found');
  const end = source.indexOf('}', block);
  const body = source.slice(block, end);
  const names = [...body.matchAll(/^\s{2}(\w+),\s*$/gm)].map((m) => m[1]);
  if (names.length === 0) die('tags.dart: no enum members extracted from TagCategory');
  return names;
}

/**
 * Builds the taxonomy artifact from the current Dart sources. Exported so
 * webapp/test/taxonomy.test.ts can rebuild it in memory and diff.
 */
export function buildTaxonomy(
  tagsSource = readFileSync(tagsPath, 'utf8'),
  trackingPreferencesSource = readFileSync(trackingPreferencesPath, 'utf8'),
  careModesSource = readFileSync(careModesPath, 'utf8'),
) {
  const categoryOrder = extractCategoryOrder(tagsSource);

  // The category → snake_case wire-name map (#259): every entry must be
  // `TagCategory.x: 'name',`.
  const wireBody = constSetOrMapBody(tagsSource, '_kCategoryWireNames', 'tags.dart');
  const wireNames = {};
  for (const match of wireBody.matchAll(/TagCategory\.(\w+):\s*'([a-z_]+)',/g)) {
    wireNames[match[1]] = match[2];
  }
  for (const category of categoryOrder) {
    if (!(category in wireNames)) {
      die(`tags.dart: no wire name for TagCategory.${category}`);
    }
  }

  // The taxonomy codes themselves. `TagCode('code', TagCategory.x, 'Display')`
  // — with one documented exception: a first argument may be a `const String
  // k...Code = '...'` reference (today `kPainFreeCode`), resolved from the
  // same file. The display never carries an apostrophe escape today; if one
  // lands, this parser fails loudly via the missing-code check below instead
  // of silently dropping the code.
  const codeConstants = {};
  for (const m of tagsSource.matchAll(/const String (k\w+Code) = '([a-z0-9_]+)';/g)) {
    codeConstants[m[1]] = m[2];
  }
  const tags = [
    ...tagsSource.matchAll(
      /TagCode\(\s*(\w+|'[a-z0-9_]+'),\s*TagCategory\.(\w+),\s*'([^']*)'/g,
    ),
  ].map((m) => {
    const raw = m[1];
    const code = raw.startsWith("'") ? raw.slice(1, -1) : codeConstants[raw];
    if (code === undefined) {
      die(
        `tags.dart: TagCode first argument '${raw}' is neither a literal nor a known k...Code constant`,
      );
    }
    return { code, category: m[2], display: m[3] };
  });
  if (tags.length < 100) {
    die(`tags.dart: only ${tags.length} TagCode entries extracted — parser is stale`);
  }
  const knownCodes = new Set(tags.map((t) => t.code));
  for (const tag of tags) {
    if (!(tag.category in wireNames)) {
      die(`tags.dart: tag '${tag.code}' carries unknown category '${tag.category}'`);
    }
  }

  // Positive "none today" assertions (never rendered as symptoms).
  const positiveAssertionCodes = ['pain_free', 'no_sex_today', 'none'].filter((code) =>
    knownCodes.has(code),
  );

  // Single-select categories: exactly one option per category per day.
  const singleSelectBody = constSetOrMapBody(
    tagsSource,
    'kSingleSelectTagCategories',
    'tags.dart',
  );
  const singleSelectCategories = [...singleSelectBody.matchAll(/TagCategory\.(\w+)/g)].map(
    (m) => m[1],
  );

  // Categories that default to hidden on a minor profile (#259's global
  // assumption #2) — an explicit stored preference overrides.
  const minorHiddenBody = constSetOrMapBody(
    trackingPreferencesSource,
    'kMinorDefaultHiddenTrackingCategories',
    'tracking_preferences.dart',
  );
  const minorDefaultHiddenCategories = [...minorHiddenBody.matchAll(/'([a-z_]+)'/g)].map(
    (m) => m[1],
  );

  // The standard care mode's category headings (#131) — the labels the day
  // sheet renders. Presentation copy owned by the app, mirrored verbatim.
  const labelsBody = constSetOrMapBody(
    careModesSource,
    '_standardCategoryLabels',
    'care_modes.dart',
  );
  const categoryLabels = {};
  for (const match of labelsBody.matchAll(/TagCategory\.(\w+):\s*'([^']+)',/g)) {
    categoryLabels[match[1]] = match[2];
  }
  for (const category of categoryOrder) {
    if (!(category in categoryLabels)) {
      die(`care_modes.dart: no standard label for TagCategory.${category}`);
    }
  }

  return {
    categories: categoryOrder.map((name) => ({
      name,
      wireName: wireNames[name],
      label: categoryLabels[name],
    })),
    tags: tags.map((tag) => ({ ...tag })),
    positiveAssertionCodes,
    singleSelectCategories,
    minorDefaultHiddenCategories,
  };
}

/** Serialises deterministically (2-space indent, trailing newline). */
export function serializeTaxonomy(taxonomy) {
  return `${JSON.stringify(taxonomy, null, 2)}\n`;
}

function main() {
  const taxonomy = buildTaxonomy();
  mkdirSync(dirname(taxonomyJsonOutPath), { recursive: true });
  writeFileSync(taxonomyJsonOutPath, serializeTaxonomy(taxonomy));
  console.log(
    `taxonomy: ${taxonomy.tags.length} codes in ${taxonomy.categories.length} categories -> ${taxonomyJsonOutPath}`,
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main();
}
