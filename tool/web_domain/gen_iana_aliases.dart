/// Regenerates `iana_aliases.dart` (issue #1273) from an IANA tzdata
/// `backward` file — the derivation, not the table, is committed so the map
/// can never silently drift from tzdata itself.
///
/// The `backward` file is the historical link set (`Link <target> <alias>`:
/// Asia/Calcutta -> Asia/Kolkata, Europe/Kiev -> Europe/Kyiv, ...). Some
/// browsers still report these pre-rename ids from
/// `Intl.DateTimeFormat().resolvedOptions().timeZone`, and package:timezone's
/// compiled `latest_10y` database drops the links while keeping the targets —
/// so the facade needs an explicit alias table or those users get
/// `unknown IANA time zone` from every date-math call.
///
/// The generator keeps exactly the load-bearing entries: aliases whose target
/// IS a location in the `latest_10y` database and whose alias name is NOT
/// (the database wins for any name it carries, so a shadowed entry would be
/// dead weight). Dropped links are reported on stdout, never silently.
///
/// Run from the repo root (tzdata release pinned in the generated header):
///
/// ```
/// curl -sO https://data.iana.org/time-zones/releases/tzdata2026e.tar.gz
/// tar -xzf tzdata2026e.tar.gz backward
/// dart run tool/web_domain/gen_iana_aliases.dart <path-to-backward>
/// ```
///
/// A `backward` file without its tarball's sibling `version` file (e.g. from
/// a distro package) needs the release passed explicitly:
/// `--tzdata-version=2026e`. With no positional argument the script reads
/// `backward` from the current directory.
library;

import 'dart:io';

import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Links tzdata has since *retired* from `backward` (commented out) that the
/// compiled `latest_10y` database still needs. tzdata 2024b demoted `GMT`
/// from link to Zone — the link is commented out of every `backward` since —
/// but timezone 0.11.1's database is generated from pre-2024b tzdata and does
/// not carry `GMT` as a location, while browsers still report `GMT` for
/// UTC-offset users. The facade's original hand-written two-entry map carried
/// exactly `UTC`/`GMT`; `UTC` is still an active `backward` link, `GMT` is
/// kept here so a regeneration cannot regress it.
const Map<String, String> _retiredLinkAliases = {'GMT': 'Etc/GMT'};

void main(List<String> args) {
  final backwardPath = args.isEmpty ? 'backward' : args.first;
  final backwardFile = File(backwardPath);
  if (!backwardFile.existsSync()) {
    stderr.writeln('backward file not found: $backwardPath');
    exitCode = 2;
    return;
  }

  final tzdataVersion = _resolveTzdataVersion(backwardFile, args);
  if (tzdataVersion == null) return; // message + exit code already set

  tzdata.initializeTimeZones();
  final locations = tz.timeZoneDatabase.locations;

  final aliases = <String, String>{};
  final droppedNoTarget = <String>[];
  final droppedShadowed = <String>[];
  for (final rawLine in backwardFile.readAsLinesSync()) {
    final line = rawLine.trim().replaceAll('\r', '');
    if (line.isEmpty || line.startsWith('#')) continue;
    // Some lines carry a trailing `#= <alias>` / `#*= ...` annotation after
    // the three fields; zone names never contain `#`, so cutting at the
    // first one is safe.
    final hash = line.indexOf('#');
    final content = (hash >= 0 ? line.substring(0, hash) : line).trim();
    final parts = content.split(RegExp(r'\s+'));
    // `backward` is a full tzdata source file (it also carries the Rule and
    // Zone lines the links resolve through); only its Link lines matter
    // here — after comment-stripping each is exactly `Link <target> <alias>`.
    if (parts.first != 'Link') continue;
    if (parts.length != 3) {
      throw StateError('unparsable Link line: "$rawLine"');
    }
    final target = parts[1];
    final alias = parts[2];
    if (alias == target) continue; // self-links carry no information
    if (!locations.containsKey(target)) {
      droppedNoTarget.add('$alias -> $target');
      continue;
    }
    if (locations.containsKey(alias)) {
      droppedShadowed.add(alias);
      continue;
    }
    if (aliases.containsKey(alias)) {
      throw StateError('duplicate alias in backward file: $alias');
    }
    aliases[alias] = target;
  }

  // The retired links go through the same filters, so a database that
  // eventually carries `GMT` itself drops the exception as shadowed.
  for (final entry in _retiredLinkAliases.entries) {
    if (locations.containsKey(entry.key)) {
      droppedShadowed.add(entry.key);
    } else if (!locations.containsKey(entry.value)) {
      droppedNoTarget.add('${entry.key} -> ${entry.value}');
    } else {
      aliases[entry.key] = entry.value;
    }
  }

  final names = aliases.keys.toList()..sort();
  final buffer = StringBuffer('''
/// GENERATED FILE — do not edit by hand.
///
/// Legacy IANA link name -> canonical zone id, derived from the IANA tzdata
/// `backward` file (release $tzdataVersion) by
/// `tool/web_domain/gen_iana_aliases.dart` (issue #1273) and filtered to the
/// `latest_10y` database this facade loads: every entry is a link name the
/// database does NOT carry whose target it DOES — exactly the names that
/// would otherwise be rejected as `unknown IANA time zone` when a browser
/// reports one from `Intl.DateTimeFormat().resolvedOptions().timeZone`.
/// One retired-link exception is merged in on top (`GMT`; see the
/// generator's `_retiredLinkAliases` for why).
///
/// Regenerate (see the generator's doc comment for the full recipe):
///
/// ```
/// dart run tool/web_domain/gen_iana_aliases.dart <path-to-backward>
/// ```
library;

/// Legacy IANA link names mapped to the canonical ids the tz database
/// carries. `UTC`/`GMT` are part of this table (tzdata's `backward` ships
/// them as links onto `Etc/UTC`/`Etc/GMT`), superseding the hand-listed
/// two-entry map the facade originally shipped.
const Map<String, String> kIanaLegacyAliases = {
''');
  for (final name in names) {
    buffer.writeln("  '$name': '${aliases[name]}',");
  }
  buffer.write('};\n');

  const outputPath = 'tool/web_domain/iana_aliases.dart';
  File(outputPath).writeAsStringSync(buffer.toString());
  stdout.writeln(
    'wrote ${aliases.length} aliases to $outputPath (tzdata $tzdataVersion)',
  );
  if (droppedNoTarget.isNotEmpty) {
    stdout.writeln(
      'dropped ${droppedNoTarget.length} links whose target the '
      'latest_10y database does not carry (still an unknown-zone error, '
      'as before):',
    );
    for (final entry in droppedNoTarget) {
      stdout.writeln('  $entry');
    }
  }
  if (droppedShadowed.isNotEmpty) {
    stdout.writeln(
      'dropped ${droppedShadowed.length} links the database itself '
      'already carries (the database wins; an entry would be dead weight): '
      '${droppedShadowed.join(', ')}',
    );
  }
}

/// The tzdata release stamp the generated header carries: the `--tzdata-version=`
/// argument wins, then a sibling `version` file (shipped in the tzdb tarball).
String? _resolveTzdataVersion(File backwardFile, List<String> args) {
  for (final arg in args) {
    const prefix = '--tzdata-version=';
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  final versionFile = File(
    '${backwardFile.parent.path}${Platform.pathSeparator}version',
  );
  if (versionFile.existsSync()) {
    final text = versionFile.readAsStringSync().trim();
    if (text.isNotEmpty) return text;
  }
  stderr.writeln(
    'no tzdata release stamp: pass --tzdata-version=<release>, or keep the '
    'version file next to the backward file',
  );
  exitCode = 2;
  return null;
}
