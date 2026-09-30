import { z } from 'zod';

/**
 * Zod schemas for the compiled Dart domain module's outputs (issue #1251).
 *
 * `lunarlogDomain.invoke` answers a JSON envelope,
 * `{"ok": true, "data": ...} | {"ok": false, "error": "..."}`, whose data
 * shapes are owned by `tool/web_domain/facade.dart` on the Dart side. These
 * schemas are the TypeScript mirror the client validates every response
 * against before use — the same boundary discipline `../lib/schemas.ts`
 * applies to Supabase rows. The parity suite (`test/domain/parity.test.ts`)
 * keeps the two sides pinned to each other through the committed fixtures,
 * so a Dart-side shape change that outdates a schema fails CI here.
 */

/** The facade's error envelope. */
export const domainErrorSchema = z.object({
  ok: z.literal(false),
  error: z.string(),
});

/** The facade's success envelope; `data` is validated per-method. */
export const domainSuccessSchema = z.object({
  ok: z.literal(true),
  data: z.unknown(),
});

export type DomainCall = <T>(method: string, requestJson: string) => T;

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'yyyy-MM-dd date');

export const cycleConfidenceSchema = z.enum(['high', 'learning', 'irregular', 'provisional']);
export type CycleConfidence = z.infer<typeof cycleConfidenceSchema>;

export const predictionBasisSchema = z.enum([
  'statistical',
  'regimenSchedule',
  'statisticalOnHormonalMethod',
]);

/** Life-stage modes (`LifecycleMode` on the Dart side). */
export const lifecycleModeSchema = z.enum([
  'tracking',
  'conceive',
  'pregnancy',
  'perimenopause',
  'postpartum',
]);

/** Birth-control method names as the facade reports them (Dart enum names). */
export const birthControlMethodSchema = z.enum([
  'none',
  'pill',
  'shot',
  'implant',
  'patch',
  'ring',
  'hormonalIud',
  'copperIud',
  'condom',
  'other',
  'unknown',
]);

export const predictedCycleSchema = z.object({
  cycleIndex: z.number().int(),
  start: isoDate,
  estimatedPeriodLengthDays: z.number().int(),
  tier: cycleConfidenceSchema,
  spreadDays: z.number(),
});

export const pmsEstimateSchema = z.object({
  meanOnsetDaysBeforeNextPeriod: z.number(),
  meanLengthDays: z.number(),
  usableIntervalCount: z.number().int(),
  tier: cycleConfidenceSchema,
  predictedStart: isoDate,
  predictedEnd: isoDate,
});

export const activePredictionSchema = z.object({
  kind: z.literal('active'),
  today: isoDate,
  lastEpisodeStart: isoDate,
  estimatedNextStart: isoDate,
  originalEstimatedNextStart: isoDate,
  averagedCycleLengths: z.array(z.number().int()),
  meanCycleLengthDays: z.number(),
  cycleDay: z.number().int(),
  duringEpisode: z.boolean(),
  completedCycleCount: z.number().int(),
  validCycleCount: z.number().int(),
  meanPeriodLengthDays: z.number(),
  spreadDays: z.number(),
  validRatio: z.number(),
  tier: cycleConfidenceSchema,
  basis: predictionBasisSchema,
  unusuallyLongCycle: z.boolean(),
  staleHistory: z.boolean(),
  daysLate: z.number().int().nullable(),
  daysUntilNextPeriod: z.number().int(),
  forecast: z.array(predictedCycleSchema),
  pms: pmsEstimateSchema.nullable(),
});

export const notEnoughHistorySchema = z.object({
  kind: z.literal('notEnoughHistory'),
  episodeCount: z.number().int(),
  completedCycleCount: z.number().int(),
  validCycleCount: z.number().int(),
  usableCycleCount: z.number().int(),
});

/** Exactly one reason is set (the Dart constructor asserts it). */
export const predictionsSuppressedSchema = z.object({
  kind: z.literal('suppressed'),
  method: birthControlMethodSchema.nullable(),
  lifecycleMode: lifecycleModeSchema.nullable(),
});

export const predictionsDisabledSchema = z.object({
  kind: z.literal('disabled'),
});

export const predictionSchema = z.discriminatedUnion('kind', [
  activePredictionSchema,
  notEnoughHistorySchema,
  predictionsSuppressedSchema,
  predictionsDisabledSchema,
]);

export type Prediction = z.infer<typeof predictionSchema>;
export type ActivePrediction = z.infer<typeof activePredictionSchema>;

export const cycleHistoryItemSchema = z.object({
  start: isoDate,
  lengthDays: z.number().int().nullable(),
  omitted: z.boolean(),
  open: z.boolean(),
  outlier: z.boolean(),
  countedInAverages: z.boolean(),
});

export const cycleHistoryViewSchema = z.object({
  items: z.array(cycleHistoryItemSchema),
  episodeCount: z.number().int(),
  completedCycleCount: z.number().int(),
  validCycleCount: z.number().int(),
  averagedCycleCount: z.number().int(),
  meanCycleLengthDays: z.number().nullable(),
  meanPeriodLengthDays: z.number().nullable(),
  variationDays: z.number().int().nullable(),
  confidence: cycleConfidenceSchema.nullable(),
});

export type CycleHistoryView = z.infer<typeof cycleHistoryViewSchema>;

export const symptomPatternSchema = z.object({
  tag: z.string(),
  totalOccurrences: z.number().int(),
  cycleCount: z.number().int(),
  /** Cycle-day keys, stringified (JSON object keys are strings). */
  frequencyByCycleDay: z.record(z.string(), z.number().int()),
  peakCycleDays: z.array(z.number().int()),
  trend: z.enum(['increasing', 'decreasing', 'stable']),
  meetsThreshold: z.boolean(),
});

export const flowPatternSchema = z.object({
  flowByCycleDay: z.record(z.string(), z.record(z.string(), z.number().int())),
  typicalPeakFlow: z.string(),
  typicalPeakDay: z.number().int(),
});

export const crampPredictionSchema = z.object({
  predictedCycleDays: z.array(z.number().int()),
  predictedDates: z.array(isoDate),
  observedCycleCount: z.number().int(),
  totalCyclesAnalyzed: z.number().int(),
  disclaimer: z.string(),
});

export const insightsReportSchema = z.object({
  symptomPatterns: z.array(symptomPatternSchema),
  flowPattern: flowPatternSchema.nullable(),
  crampPrediction: crampPredictionSchema.nullable(),
  analyzedCycleCount: z.number().int(),
  hasEnoughData: z.boolean(),
});

export type InsightsReport = z.infer<typeof insightsReportSchema>;

export const dateValidationSchema = z.object({
  status: z.enum(['valid', 'futureDate', 'beforeBirthYear']),
});

/**
 * The export document's top-level shape. The profile payloads inside are
 * the phone importer's own dialect and stay opaque records here — the web
 * client's job is to produce the document, not to read it back.
 */
export const exportDocumentSchema = z.object({
  schemaVersion: z.number().int(),
  exportedAt: z.string(),
  app: z.object({ name: z.string(), version: z.string() }),
  profiles: z.array(z.record(z.string(), z.unknown())),
});

export type ExportDocument = z.infer<typeof exportDocumentSchema>;

export const inviteLinkSchema = z.object({
  code: z.string(),
  profileId: z.string().nullable(),
  kind: z.string().nullable(),
  isClaim: z.boolean(),
  isPrediction: z.boolean(),
});

export type InviteLink = z.infer<typeof inviteLinkSchema>;
