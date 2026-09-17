/// Operator-run test-account seeder for lunarlog (issue #710).
///
/// Populates a fabricated, allowlisted test account with 18 months of
/// realistic sample data by signing in as that account and writing through
/// the real `sync_push` RPC and the real sharing RPCs — every server-side
/// invariant (CHECKs, triggers, RLS, role ladders) is exercised exactly as
/// the app exercises it, and a fresh device install syncs the data down
/// without rejections. Never shipped in the app; tool-only.
///
/// Usage (from the repo root; `.env` supplies the keys — names only, see
/// docs/ops/seed-test-account.md):
///
/// ```
/// dart run tool/seed_test_accounts/main.dart [--months 18] [--seed 42]
///   [--reset-and-reseed] [--state-file .seed-state.json]
///   [--emit-pgtap supabase/tests/seed_sync_push_sample_test.sql]
/// ```
///
/// `--emit-pgtap` performs no network access: it regenerates the committed
/// pgTAP fixture from the payload generator (see that file's header).
library;

import 'dart:io';

import 'payload_generator.dart';
import 'pgtap_emitter.dart';
import 'seed_config.dart';
import 'seeder.dart';
import 'supabase_seed_client.dart';

const String _regenCommand =
    'dart run tool/seed_test_accounts/main.dart --emit-pgtap';

/// Loads the repo-root `.env` (if present) and merges it under the real
/// environment — real env wins, matching the CLI conventions.
Map<String, String> _loadEnv(String repoRoot) {
  final merged = <String, String>{};
  final envFile = File('$repoRoot/.env');
  if (envFile.existsSync()) {
    for (final line in envFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      merged[key] = value;
    }
  }
  merged.addAll(Platform.environment);
  return merged;
}

class _Args {
  _Args(List<String> raw) {
    for (var i = 0; i < raw.length; i++) {
      final arg = raw[i];
      if (arg == '--reset-and-reseed') {
        resetAndReseed = true;
      } else if (arg == '--months') {
        _requireValue(raw, i, arg);
        final parsed = int.tryParse(raw[++i]);
        if (parsed == null) {
          throw const FormatException('--months requires an integer');
        }
        months = parsed;
      } else if (arg == '--seed') {
        _requireValue(raw, i, arg);
        final parsed = int.tryParse(raw[++i]);
        if (parsed == null) {
          throw const FormatException('--seed requires an integer');
        }
        seed = parsed;
      } else if (arg == '--state-file') {
        _requireValue(raw, i, arg);
        stateFile = raw[++i];
      } else if (arg == '--emit-pgtap') {
        _requireValue(raw, i, arg);
        emitPgtapPath = raw[++i];
      } else {
        throw SeedConfigException('unknown argument: $arg');
      }
    }
  }

  static void _requireValue(List<String> raw, int i, String name) {
    if (i + 1 >= raw.length) {
      throw SeedConfigException('$name requires a value');
    }
  }

  bool resetAndReseed = false;
  int? months;
  int? seed;
  String? stateFile;
  String? emitPgtapPath;
}

Future<void> main(List<String> arguments) async {
  exitCode = 0;
  try {
    final args = _Args(arguments);

    if (args.emitPgtapPath != null) {
      final content = buildPgtapFixture();
      File(args.emitPgtapPath!).writeAsStringSync(content);
      // ignore: avoid_print
      print('[seed] wrote ${args.emitPgtapPath} ($_regenCommand)');
      return;
    }

    final repoRoot = Directory.current.path;
    final env = _loadEnv(repoRoot);
    final config = buildSeedToolConfig(env);

    final months = args.months == null
        ? 18
        : (args.months! < kMinSeedMonths ? kMinSeedMonths : args.months!);
    final seed = args.seed ?? 42;

    final seeder = TestAccountSeeder(SeederDeps(
      config: config,
      client: SupabaseSeedClient(config: config),
      months: months,
      seed: seed,
      statePath: args.stateFile ?? '$repoRoot/.seed-state.json',
      // ignore: avoid_print
      logger: (line) => print(line),
      resetAndReseed: args.resetAndReseed,
    ));
    final summary = await seeder.run();
    // ignore: avoid_print
    print('[seed] done: ${(summary['profiles'] as List).length} profile(s), '
        '${summary['dayEntries']} live day entries readable back, '
        '${summary['syncPushCalls']} sync_push calls, rejected == [] throughout');
  } on SeedConfigException catch (e) {
    // Config refusals (allowlist etc.) happen before any network call.
    // ignore: avoid_print
    print('[seed] refusing to run: $e');
    exitCode = 2;
  } on SeedRunException catch (e) {
    // ignore: avoid_print
    print('[seed] aborted: $e');
    exitCode = 3;
  } on SeedHttpException catch (e) {
    // ignore: avoid_print
    print('[seed] failed: $e');
    exitCode = 4;
  } on FormatException catch (e) {
    // Corrupt state file / bad --months value.
    // ignore: avoid_print
    print('[seed] failed: $e');
    exitCode = 5;
  }
}
