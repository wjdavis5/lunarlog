/// The per-method CRAP gate (plan U3, R5/R6/R7).
///
/// CRAP(m) = comp(m)^2 * (1 - cov(m)/100)^3 + comp(m). `comp(m)` is McCabe
/// cyclomatic complexity from `package:analyzer`'s syntactic AST (KTD3 — not
/// DCM, to avoid its commercial licensing). `cov(m)` comes from intersecting
/// the method's line range with the filtered lcov `DA` records (KTD2 —
/// `flutter test --coverage`'s lcov carries no `FN`/`FNDA` function records
/// at all, verified empirically, so per-method coverage can't come from
/// those the way the issue's original design assumed).
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'coverage_filter.dart';
import 'exclusions.dart';

const double crapThreshold = 10.0;

class CrapOffender {
  const CrapOffender({
    required this.filePath,
    required this.methodName,
    required this.line,
    required this.complexity,
    required this.coveragePercent,
    required this.crapScore,
  });

  final String filePath;
  final String methodName;
  final int line;
  final int complexity;
  final double coveragePercent;
  final double crapScore;
}

class CrapGateResult {
  const CrapGateResult({required this.passed, required this.offenders});

  final bool passed;

  /// Every method scoring above [crapThreshold], sorted descending by
  /// score (R7: "report every method over the threshold").
  final List<CrapOffender> offenders;
}

double _crapScore(int complexity, double coveragePercent) {
  final comp = complexity.toDouble();
  final uncovered = 1 - coveragePercent / 100;
  return comp * comp * uncovered * uncovered * uncovered + comp;
}

/// Counts McCabe decision points inside [body] (a method/function/
/// constructor body — not a whole file, so a nested closure's decision
/// points roll up into the enclosing method's score rather than being
/// double-registered as a separate unit; see the plan's U3 Approach).
class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  int decisionPoints = 0;

  @override
  void visitIfStatement(IfStatement node) {
    decisionPoints++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    decisionPoints++;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    decisionPoints++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    decisionPoints++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    decisionPoints++;
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    decisionPoints++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    // The arm of a switch *expression* (`switch (x) { a => ..., b => ... }`)
    // — a distinct AST node from SwitchCase/SwitchPatternCase (which cover
    // switch *statements*). Without this override, a method whose branching
    // is expressed as a switch expression is silently undercounted.
    decisionPoints++;
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    decisionPoints++;
    super.visitCatchClause(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.lexeme;
    if (op == '&&' || op == '||' || op == '??') {
      decisionPoints++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    decisionPoints++;
    super.visitConditionalExpression(node);
  }
}

/// One scored method/function/constructor.
class _ScoredMethod {
  _ScoredMethod(this.name, this.startLine, this.endLine, this.complexity);

  final String name;
  final int startLine;
  final int endLine;
  final int complexity;
}

int _complexityOf(FunctionBody body) {
  final visitor = _ComplexityVisitor();
  body.accept(visitor);
  return 1 + visitor.decisionPoints;
}

/// Every scoreable method/constructor/top-level function in [unit] —
/// abstract/interface signatures (`EmptyFunctionBody`) are skipped per the
/// plan U3 Approach step 5 ("has no complexity to compute and no coverage
/// to measure").
List<_ScoredMethod> _methodsIn(CompilationUnit unit, LineInfo lineInfo) {
  final methods = <_ScoredMethod>[];

  void addIfScoreable(String name, AstNode declaration, FunctionBody body) {
    if (body is EmptyFunctionBody) return;
    final startLine = lineInfo.getLocation(declaration.offset).lineNumber;
    final endLine = lineInfo.getLocation(declaration.end).lineNumber;
    methods.add(_ScoredMethod(name, startLine, endLine, _complexityOf(body)));
  }

  for (final declaration in unit.declarations) {
    if (declaration is FunctionDeclaration) {
      addIfScoreable(
        declaration.name.lexeme,
        declaration,
        declaration.functionExpression.body,
      );
    } else if (declaration is ClassDeclaration) {
      // analyzer 14.x: primary-constructor support moved the class name to
      // `namePart.typeName` and members under `body.members` (previously
      // `ClassDeclaration.name`/`.members` directly).
      final className = declaration.namePart.typeName.lexeme;
      for (final member in declaration.body.members) {
        if (member is MethodDeclaration) {
          addIfScoreable(
            '$className.${member.name.lexeme}',
            member,
            member.body,
          );
        } else if (member is ConstructorDeclaration) {
          final ctorName = member.name?.lexeme;
          addIfScoreable(
            '$className.${ctorName ?? "<constructor>"}',
            member,
            member.body,
          );
        }
      }
    } else if (declaration is MixinDeclaration) {
      for (final member in declaration.body.members) {
        if (member is MethodDeclaration) {
          addIfScoreable(
            '${declaration.name.lexeme}.${member.name.lexeme}',
            member,
            member.body,
          );
        }
      }
    } else if (declaration is ExtensionDeclaration) {
      for (final member in declaration.body.members) {
        if (member is MethodDeclaration) {
          final onName = declaration.name?.lexeme ?? '<extension>';
          addIfScoreable(
            '$onName.${member.name.lexeme}',
            member,
            member.body,
          );
        }
      }
    }
  }
  return methods;
}

/// Coverage for [method] from the file's filtered `DA` records: only lines
/// that have a `DA` record at all count toward the denominator (KTD2 — a
/// signature line with no record isn't "uncovered", it's non-executable,
/// same convention `coverage_gate.dart` uses).
double _coverageOf(_ScoredMethod method, Map<int, int> daHits) {
  var total = 0;
  var hit = 0;
  for (var line = method.startLine; line <= method.endLine; line++) {
    final count = daHits[line];
    if (count != null) {
      total++;
      if (count > 0) hit++;
    }
  }
  if (total == 0) return 100.0; // no measurable lines: not a coverage risk.
  return hit / total * 100.0;
}

/// Runs the CRAP gate over every non-excluded file under `lib/`, using
/// [filtered] (already produced by [filteredCoverageFromFile] — KTD6, the
/// same filtered pass the coverage gate uses).
CrapGateResult evaluateCrapGate(
  Map<String, FileCoverage> filtered, {
  Directory? libDir,
}) {
  final offenders = <CrapOffender>[];

  // Keyed by normalized path once, up front, so each file below is an O(1)
  // lookup instead of a per-file rescan of the whole filtered map (the
  // scan cost would otherwise be O(files x coverage entries)) — `filtered`
  // doesn't change across the loop below.
  final normalizedFiltered = {
    for (final entry in filtered.entries)
      normalizeSourcePath(entry.key): entry.value,
  };

  for (final libFile in nonExcludedLibDartFiles(libDir)) {
    final parsed = parseFile(
      path: libFile.file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
    );
    final methods = _methodsIn(parsed.unit, parsed.lineInfo);
    if (methods.isEmpty) continue;

    final libRelativePath = libFile.libRelativePath;
    final daHits = normalizedFiltered[libRelativePath]?.daHits ?? const {};

    for (final method in methods) {
      final coverage = _coverageOf(method, daHits);
      final score = _crapScore(method.complexity, coverage);
      if (score > crapThreshold) {
        offenders.add(
          CrapOffender(
            filePath: libRelativePath,
            methodName: method.name,
            line: method.startLine,
            complexity: method.complexity,
            coveragePercent: coverage,
            crapScore: score,
          ),
        );
      }
    }
  }

  offenders.sort((a, b) => b.crapScore.compareTo(a.crapScore));
  return CrapGateResult(passed: offenders.isEmpty, offenders: offenders);
}

void printCrapReport(CrapGateResult result) {
  final status = result.passed ? 'PASS' : 'FAIL';
  // ignore: avoid_print
  print(
    '[crap] $status: ${result.offenders.length} method(s) over the CRAP '
    '${crapThreshold.toStringAsFixed(0)} threshold',
  );
  for (final o in result.offenders) {
    // ignore: avoid_print
    print(
      '[crap]   ${o.crapScore.toStringAsFixed(1)}  ${o.filePath}:${o.line}  '
      '${o.methodName}  (complexity ${o.complexity}, '
      '${o.coveragePercent.toStringAsFixed(1)}% covered)',
    );
  }
}
