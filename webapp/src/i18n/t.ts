import { useIntl } from 'react-intl';

import type { MessageId } from './message-ids';

/**
 * The translated-string accessor. The id parameter is the generated
 * `MessageId` union — a typo is a type error, and the no-typed-copy ESLint
 * ban keeps literals out of TSX, so this hook is the only door to
 * user-facing copy (issue #1249).
 */
export type TFunction = (
  id: MessageId,
  values?: Record<string, string | number | Date>,
) => string;

export function useT(): TFunction {
  const intl = useIntl();
  return (id, values) => intl.formatMessage({ id }, values);
}
