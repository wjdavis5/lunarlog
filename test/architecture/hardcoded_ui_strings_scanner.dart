/// Pure Dart scanner backing `hardcoded_ui_strings_test.dart` (issue
/// #460): detects string-literal user-facing copy in `lib/ui/` — a
/// first-positional string literal argument to `Text(` or `Tooltip(`
/// (which subsumes `SnackBar(content: Text('...'))`, since that is just a
/// `Text(` call in a named argument).
///
/// Extracted into its own dependency-free library (same posture as
/// `theme_wiring_test.dart`'s inline detector, but shareable) so the
/// detector gets its own falsification coverage and could be reused by a
/// burn-down tool without duplicating logic.
///
/// The scanner is a tiny hand-rolled lexer rather than a regex over the
/// raw source because the things it must NOT be fooled by — doc comments
/// that mention `Text(`, string literals that contain `//` (URLs), and
/// interpolations that themselves contain quotes (`'${f('x')}'`) — all
/// require knowing whether a character is inside a string or a comment.
/// The lexer walks the source once, tracking comments, string literals
/// (single/double/triple/raw), and `${...}` interpolation nesting:
///
/// * `//` and `/* ... */` comments are skipped entirely, so a `Text('...')
///   in a doc comment is never detected (and prose in a comment can never
///   *hide* a real call either).
/// * String literals at code level are skipped (unless they are the
///   first argument of a `Text(`/`Tooltip(` call), so a source string
///   containing the text `Text('x')` is never a false positive.
/// * Interpolation bodies are walked with brace/quote awareness, so
///   `'a ${foo('b')} c'` reads as one literal, not three fragments.
library;

/// A detected hardcoded UI string literal.
class HardcodedUiString {
  const HardcodedUiString({required this.value, required this.line});

  /// The literal's value with quotes/raw prefix/escape handling left
  /// unresolved (interpolation sigils stay — the value is only used for
  /// the has-letters test and failure messages, not for evaluation).
  final String value;

  /// 1-based line of the literal's opening quote.
  final int line;

  @override
  String toString() => 'line $line: $value';
}

bool _isIdentStart(int c) =>
    (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F;

bool _isIdentPart(int c) =>
    _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

bool _isWs(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isQuote(int c) => c == 0x27 /* ' */ || c == 0x22 /* " */;

/// Removes interpolation spans (`${...}`, `$identifier`) from a literal's
/// raw [value], leaving only the literal-prose portions. Used by
/// [isHardcodedUiCopy] so that a pure interpolation such as
/// `'${date.day}'` — whose only "letters" belong to variable names, not
/// to copy — is not treated as hardcoded UI copy.
String stripInterpolations(String value) {
  final buf = StringBuffer();
  var i = 0;
  while (i < value.length) {
    final c = value.codeUnitAt(i);
    if (c == 0x24 /* $ */ && i + 1 < value.length) {
      final next = value.codeUnitAt(i + 1);
      if (next == 0x7B /* { */) {
        var depth = 1;
        var j = i + 2;
        while (j < value.length && depth > 0) {
          final b = value.codeUnitAt(j);
          if (b == 0x7B /* { */) depth++;
          if (b == 0x7D /* } */) depth--;
          j++;
        }
        i = j;
        continue;
      }
      if (_isIdentStart(next)) {
        var j = i + 1;
        while (j < value.length && _isIdentPart(value.codeUnitAt(j))) {
          j++;
        }
        i = j;
        continue;
      }
    }
    buf.writeCharCode(c);
    i++;
  }
  return buf.toString();
}

/// Whether [value] counts as translatable UI copy at all: after
/// interpolation spans are stripped, the literal must contain at least
/// one ASCII letter. Literals with no letters — pure symbols,
/// punctuation, digits, whitespace, such as `'…'`, `'·'`, `'-'`, `''`,
/// `'$count'`, or `'${date.day}'` — are not localized copy in any
/// language and are excluded, keeping the allowlist honest (issue
/// #460's false-positive escape valve).
bool isHardcodedUiCopy(String value) =>
    RegExp('[A-Za-z]').hasMatch(stripInterpolations(value).trim());

/// Every string literal anywhere in [source] — not just `Text(`-argument
/// position — filtered by [isHardcodedUiCopy]. Comment-aware (a literal
/// mentioned in a doc comment never matches) and interpolation-aware (a
/// nested literal inside `'${f('x')}'` is not separately reported), so a
/// new copy string can never hide in a helper's `return`, a const
/// initializer, or a named argument the positional scan does not visit.
/// `import`/`export`/`part` directive URIs are not literals at all and are
/// skipped.
///
/// Issue #1004 (tranche 5): the fully-migrated copy modules are held to
/// this stricter scan via [_helperCopyFileLiterals] in
/// `hardcoded_ui_strings_test.dart`, because the burn-down there moved
/// exactly this class of literals (string consts and copy tables
/// resolved outside a `Text(` argument). Unlike the positional scan,
/// nothing is filtered out by shape: the per-file allowlist enumerates
/// every *remaining* non-copy literal (ValueKey names, observability
/// tags, assertion messages) so a new string — copy or not — needs a
/// deliberate, reviewed allowlist entry.
List<HardcodedUiString> allSourceStringLiterals(String source) {
  final found = <HardcodedUiString>[];
  var i = 0;
  var line = 1;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    if (c == 0x0A) {
      line++;
      i++;
      continue;
    }
    if (c == 0x2F /* / */ && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x2F /* / */) {
        while (i < source.length && source.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A /* * */) {
        i += 2;
        while (i + 1 < source.length &&
            !(source.codeUnitAt(i) == 0x2A &&
                source.codeUnitAt(i + 1) == 0x2F)) {
          if (source.codeUnitAt(i) == 0x0A) line++;
          i++;
        }
        i += 2;
        continue;
      }
    }
    final isRawPrefix = c == 0x72 /* r */ &&
        i + 1 < source.length &&
        _isQuote(source.codeUnitAt(i + 1));
    if (_isQuote(c) || isRawPrefix) {
      final quoteIndex = isRawPrefix ? i + 1 : i;
      if (_precededByDirectiveKeyword(source, i)) {
        // `import '…'` / `export '…'` / `part '…'` — a URI, not copy.
        final lit = _readLiteral(source, quoteIndex);
        line += '\n'.allMatches(lit.value).length;
        i = lit.end;
        continue;
      }
      final lit = _readLiteral(source, quoteIndex);
      final literalLine = line;
      if (isHardcodedUiCopy(lit.value)) {
        found.add(HardcodedUiString(value: lit.value, line: literalLine));
      }
      line += '\n'.allMatches(lit.value).length;
      i = lit.end;
      continue;
    }
    i++;
  }
  return found;
}

/// Whether the literal starting at [i] is a directive URI: the nearest
/// preceding word (skipping whitespace) is `import`, `export`, or `part`.
bool _precededByDirectiveKeyword(String source, int i) {
  var j = i - 1;
  while (j >= 0 && _isWs(source.codeUnitAt(j))) {
    j--;
  }
  final end = j + 1;
  while (j >= 0 && (_isIdentPart(source.codeUnitAt(j)))) {
    j--;
  }
  final word = source.substring(j + 1, end);
  return word == 'import' || word == 'export' || word == 'part';
}

/// Result of [_readLiteral]: the index just past the closing quote and
/// the raw text between the quotes.
class _Literal {
  const _Literal(this.end, this.value);
  final int end;
  final String value;
}

/// Reads the string literal whose first token (after an optional raw `r`
/// prefix) starts at [i], which must point at the `r` or the opening
/// quote. Handles single/double/triple quotes, raw prefixes, backslash
/// escapes, and `${...}` interpolation that may nest quotes and braces.
_Literal _readLiteral(String s, int i) {
  var raw = false;
  if (s.codeUnitAt(i) == 0x72 /* r */) {
    raw = true;
    i++;
  }
  final q = s.codeUnitAt(i);
  final triple = i + 2 < s.length &&
      s.codeUnitAt(i + 1) == q &&
      s.codeUnitAt(i + 2) == q;
  final contentStart = i + (triple ? 3 : 1);
  var j = contentStart;
  while (j < s.length) {
    final c = s.codeUnitAt(j);
    if (!raw && c == 0x5C /* \ */) {
      j += 2; // escape: skip the escaped character
      continue;
    }
    if (!raw && c == 0x24 /* $ */ && j + 1 < s.length) {
      final next = s.codeUnitAt(j + 1);
      if (next == 0x7B /* { */) {
        j = _skipInterpolation(s, j + 2);
        continue;
      }
      // `$identifier` — ordinary content, no special handling needed.
    }
    if (c == q) {
      if (!triple) {
        return _Literal(j + 1, s.substring(contentStart, j));
      }
      if (j + 2 < s.length &&
          s.codeUnitAt(j + 1) == q &&
          s.codeUnitAt(j + 2) == q) {
        return _Literal(j + 3, s.substring(contentStart, j));
      }
    }
    j++;
  }
  // Unterminated literal (should not happen in analyzed code): consume
  // the rest so the scanner still terminates.
  return _Literal(s.length, s.substring(contentStart, s.length));
}

/// Skips an interpolation body starting just past its opening `{` at
/// [i]; returns the index just past the matching `}`. Nested strings and
/// nested braces inside the body are respected so quotes in
/// `'${list.map((e) => 'x')}'` do not end the outer literal early.
int _skipInterpolation(String s, int i) {
  var depth = 1;
  var j = i;
  while (j < s.length && depth > 0) {
    final c = s.codeUnitAt(j);
    if (c == 0x7B /* { */) {
      depth++;
    } else if (c == 0x7D /* } */) {
      depth--;
      if (depth == 0) return j + 1;
    } else if (_isQuote(c)) {
      j = _readLiteral(s, j).end;
      continue;
    } else if (c == 0x2F /* / */ && j + 1 < s.length) {
      final next = s.codeUnitAt(j + 1);
      if (next == 0x2F /* / */) {
        while (j < s.length && s.codeUnitAt(j) != 0x0A) {
          j++;
        }
        continue;
      }
      if (next == 0x2A /* * */) {
        j += 2;
        while (j + 1 < s.length &&
            !(s.codeUnitAt(j) == 0x2A && s.codeUnitAt(j + 1) == 0x2F)) {
          j++;
        }
        j += 2;
        continue;
      }
    }
    j++;
  }
  return j;
}

/// Scans [source] (Dart file contents) and returns every first-positional
/// string-literal argument to a `Text(` or `Tooltip(` call, filtered by
/// [isHardcodedUiCopy]. Line numbers are 1-based.
///
/// [namedArgs] (issue #1004, tranche 1) additionally records a
/// string-literal value for any identifier in the set written as a named
/// argument or map entry (`labelText: '...'`, `title: '...'`), which the
/// default `Text(`/`Tooltip(` scan does not see. It defaults to empty so
/// the global backlog scan is unchanged; a directory that has burned all
/// of its positional literals (starting with `lib/ui/sharing/`) opts in to
/// the stricter check.
List<HardcodedUiString> scanHardcodedUiStrings(
  String source, {
  Set<String> namedArgs = const {},
}) {
  final found = <HardcodedUiString>[];
  var i = 0;
  var line = 1;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    if (c == 0x0A) {
      line++;
      i++;
      continue;
    }
    // Line comment: skip to end of line (the newline is handled above).
    if (c == 0x2F /* / */ && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x2F /* / */) {
        while (i < source.length && source.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A /* * */) {
        i += 2;
        while (i + 1 < source.length &&
            !(source.codeUnitAt(i) == 0x2A &&
                source.codeUnitAt(i + 1) == 0x2F)) {
          if (source.codeUnitAt(i) == 0x0A) line++;
          i++;
        }
        i += 2;
        continue;
      }
    }
    // A string literal at plain code level is skipped (only a literal
    // directly in a `Text(`/`Tooltip(` argument position is recorded).
    if (_isQuote(c)) {
      final lit = _readLiteral(source, i);
      final newlines = '\n'.allMatches(lit.value).length;
      line += newlines;
      i = lit.end;
      continue;
    }
    // Identifier: the only two that matter are the widget constructors.
    if (_isIdentStart(c)) {
      final start = i;
      while (i < source.length && _isIdentPart(source.codeUnitAt(i))) {
        i++;
      }
      final ident = source.substring(start, i);
      if (ident == 'Text' || ident == 'Tooltip') {
        var k = i;
        while (k < source.length && _isWs(source.codeUnitAt(k))) {
          k++;
        }
        final atOpenParen = k < source.length && source.codeUnitAt(k) == 0x28;
        if (atOpenParen) {
          var a = k + 1;
          while (a < source.length && _isWs(source.codeUnitAt(a))) {
            a++;
          }
          final rawOrQuote = a < source.length
              ? source.codeUnitAt(a)
              : 0;
          final isLiteralArg = _isQuote(rawOrQuote) ||
              (rawOrQuote == 0x72 /* r */ &&
                  a + 1 < source.length &&
                  _isQuote(source.codeUnitAt(a + 1)));
          if (isLiteralArg) {
            final lit = _readLiteral(source, a);
            final literalLine = line + '\n'
                .allMatches(source.substring(start, a))
                .length;
            if (isHardcodedUiCopy(lit.value)) {
              found.add(
                HardcodedUiString(value: lit.value, line: literalLine),
              );
            }
            line += '\n'.allMatches(lit.value).length;
            i = lit.end;
            continue;
          }
        }
      } else if (namedArgs.contains(ident)) {
        // `ident: 'literal'` — a named argument or map entry. Skipped
        // unless the caller opted this identifier into [namedArgs].
        var k = i;
        while (k < source.length && _isWs(source.codeUnitAt(k))) {
          k++;
        }
        final atColon = k < source.length && source.codeUnitAt(k) == 0x3A;
        if (atColon) {
          var a = k + 1;
          while (a < source.length && _isWs(source.codeUnitAt(a))) {
            a++;
          }
          final rawOrQuote = a < source.length
              ? source.codeUnitAt(a)
              : 0;
          final isLiteralArg = _isQuote(rawOrQuote) ||
              (rawOrQuote == 0x72 /* r */ &&
                  a + 1 < source.length &&
                  _isQuote(source.codeUnitAt(a + 1)));
          if (isLiteralArg) {
            final lit = _readLiteral(source, a);
            final literalLine = line + '\n'
                .allMatches(source.substring(start, a))
                .length;
            if (isHardcodedUiCopy(lit.value)) {
              found.add(
                HardcodedUiString(value: lit.value, line: literalLine),
              );
            }
            line += '\n'.allMatches(lit.value).length;
            i = lit.end;
            continue;
          }
        }
      }
      continue;
    }
    i++;
  }
  return found;
}
