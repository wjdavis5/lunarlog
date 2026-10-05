import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';

import type { DomainModule } from '../../src/domain/client';

/**
 * Loads the **compiled** Dart domain module the way a test can: the dart2js
 * script is run in a bare context carrying the `self` global it writes to,
 * and the `lunarlogDomain` it installs there is handed back.
 *
 * The parity suite uses it to pin the module to the committed fixtures; a
 * page test uses it when the thing under test is what the real rules say
 * about a snapshot, not what a canned envelope says.
 *
 * Requires the module to be built first (CI does this before `npm test`;
 * see webapp/README.md):
 *   dart compile js -O2 tool/web_domain/main.dart \
 *     -o webapp/public/domain/lunarlog_domain.js
 */
export function loadDomainModule(): DomainModule {
  const code = readFileSync(
    join(import.meta.dirname, '..', '..', 'public', 'domain', 'lunarlog_domain.js'),
    'utf8',
  );
  const sandbox: Record<string, unknown> = { self: {}, console };
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox, { filename: 'lunarlog_domain.js' });
  const module = (sandbox as { self: { lunarlogDomain?: DomainModule } }).self.lunarlogDomain;
  if (!module || typeof module.invoke !== 'function') {
    throw new Error(
      'public/domain/lunarlog_domain.js did not install lunarlogDomain — rebuild the module: ' +
        'dart compile js -O2 tool/web_domain/main.dart -o webapp/public/domain/lunarlog_domain.js',
    );
  }
  return module;
}
