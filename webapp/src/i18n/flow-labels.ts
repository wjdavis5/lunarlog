import type { FlowLevel } from '../lib/day/payloads';
import type { TFunction } from './t';

/**
 * The catalogue id for each flow level's label (the day editor's chips,
 * issue #1254; also the insights flow line, issue #1822). One map, so a
 * level's wording cannot differ between the editor and the report.
 */
export const FLOW_LABEL_IDS: Record<FlowLevel, Parameters<TFunction>[0]> = {
  none: 'flowLevelNone',
  spotting: 'flowLevelSpotting',
  not_bleeding: 'flowLevelNotBleeding',
  light: 'flowLevelLight',
  medium: 'flowLevelMedium',
  heavy: 'flowLevelHeavy',
  super_heavy: 'flowLevelSuperHeavy',
};
