import 'dart:convert';
import 'dart:io';

import '../test/conformance/fixtures.dart';
import 'sha256.dart';

const _supportedForms = <String>{
  '.', '?', '?//', ';', ',', ':', '|', '+', '-', '*', '/', '%', r'$', '<', '>',
  '!=', '==', '//', '<=', '>=', '..', 'as', 'if', 'then', 'else', 'elif',
  'and', 'or', 'end', 'reduce', 'foreach', 'try', 'catch', 'label', 'break',
};
const _deferredForms = <String>{
  '@format', r'$__loc__', 'import', 'include', 'module', 'assignment', '|=',
  '+=', '-=', '*=', '/=', '%=', '//=',
};
const _m1BytecodedOverloads = <String>{'empty/0', 'not/0', 'last/1', 'range/2'};
const _m1NativeOverloads = <String>{'error/0', 'tostring/0'};
const _m1JqOverloads = <String>{
  'error/1',
  'select/1',
  'recurse/0',
  'recurse/1',
  'recurse/2',
  'range/1',
  'range/3',
  'while/2',
  'until/2',
  'limit/2',
  'skip/2',
  'first/0',
  'first/1',
  'last/0',
  'nth/1',
  'nth/2',
  'repeat/1',
};
const _m1OverloadDependencies = <String, List<String>>{
  'error/1': <String>['error/0'],
  'select/1': <String>['empty/0'],
  'recurse/0': <String>['recurse/1', 'r/0'],
  'recurse/1': <String>['r/0'],
  'recurse/2': <String>['select/1', 'r/0', 'empty/0'],
  'range/1': <String>['range/2'],
  'range/3': <String>['while/2', '_while/0', 'empty/0'],
  'while/2': <String>['_while/0', 'empty/0'],
  'until/2': <String>['_until/0'],
  'limit/2': <String>[
    'foreach/3', 'empty/0', 'error/1', 'error/0', 'label', 'break',
  ],
  'skip/2': <String>['foreach/3', 'empty/0', 'error/1', 'error/0'],
  'first/1': <String>['label', 'break'],
  'nth/2': <String>[
    'skip/2',
    'first/1',
    'error/1',
    'error/0',
    'foreach/3',
    'empty/0',
    'label',
    'break',
  ],
  'repeat/1': <String>['_repeat/0'],
};
const _jqDefinedNames = <String>{
  'halt_error', 'error', 'map', 'select', 'sort_by', 'group_by', 'unique_by',
  'max_by', 'min_by', 'add', 'del', 'abs', '_assign', '_modify', 'map_values',
  'recurse', 'to_entries', 'from_entries', 'with_entries', 'reverse', 'indices',
  'index', 'rindex', 'paths', 'isfinite', 'arrays', 'objects', 'iterables',
  'booleans', 'numbers', 'normals', 'finites', 'strings', 'nulls', 'values',
  'scalars', 'join', '_flatten', 'flatten', 'range', 'fromdateiso8601',
  'todateiso8601', 'fromdate', 'todate', 'ltrimstr', 'rtrimstr', 'trimstr',
  'match', 'test', 'capture', 'scan', 'splits', 'split', 'sub', 'gsub', 'while',
  'until', 'limit', 'skip', 'first', 'isempty', 'all', 'any', 'nth', 'last',
  'combinations', 'transpose', 'in', 'inside', 'repeat', 'inputs',
  'ascii_downcase', 'ascii_upcase', 'truncate_stream', 'fromstream', 'tostream',
  'walk', 'pick', 'debug', 'INDEX', 'JOIN', 'IN',
};
const _nativeNames = <String>{
  '_negate', '_plus', '_minus', '_multiply', '_divide', '_mod', '_equal',
  '_notequal', '_less', '_greater', '_lesseq', '_greatereq', 'tojson', 'fromjson',
  'tonumber', 'toboolean', 'tostring', 'keys', 'keys_unsorted', 'startswith',
  'endswith', 'split', 'explode', 'implode', '_strindices', 'trim', 'ltrim',
  'rtrim', 'setpath', 'getpath', 'delpaths', 'has', 'contains', 'length',
  'utf8bytelength', 'type', 'isinfinite', 'isnan', 'isnormal', 'infinite', 'nan',
  'sort', '_sort_by_impl', '_group_by_impl', 'unique', '_unique_by_impl', 'bsearch',
  'min', 'max', '_min_by_impl', '_max_by_impl', 'error', 'format', 'env', 'halt',
  'halt_error', 'get_search_list', 'get_prog_origin', 'get_jq_origin',
  '_match_impl', 'modulemeta', 'input', 'debug', 'stderr', 'strptime', 'strftime',
  'strflocaltime', 'mktime', 'gmtime', 'localtime', 'now', 'input_filename',
  'input_line_number', 'have_decnum', 'have_literal_numbers', 'builtins',
};
const _mathNames = <String>{
  'acos', 'acosh', 'asin', 'asinh', 'atan', 'atan2', 'atanh', 'cbrt', 'cos',
  'cosh', 'exp', 'exp2', 'floor', 'hypot', 'j0', 'j1', 'log', 'log10', 'log2',
  'pow', 'remainder', 'sin', 'sinh', 'sqrt', 'tan', 'tanh', 'tgamma', 'y0', 'y1',
  'jn', 'yn', 'ceil', 'copysign', 'drem', 'erf', 'erfc', 'exp10', 'expm1',
  'fabs', 'fdim', 'fma', 'fmax', 'fmin', 'fmod', 'gamma', 'lgamma', 'log1p',
  'logb', 'nearbyint', 'nextafter', 'nexttoward', 'rint', 'round', 'scalb',
  'scalbln', 'significand', 'trunc', 'ldexp', 'modf', 'frexp', 'lgamma_r',
};
const _bytecodedNames = <String>{'empty', 'not', 'path', 'last', 'range'};
const _builtinListNames = <String>{'builtins'};
const _deferredSpecialBindings = <String>{'ENV', 'ARGS'};

void _requireSha256(String path, String expected) {
  final actual = sha256Hex(File(path).readAsBytesSync());
  if (actual != expected) {
    throw StateError(
      'Pinned input hash mismatch for $path; expected $expected, got $actual.',
    );
  }
}

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'usage: dart run tool/reference_classification.dart <jq.test> <man.test> <output.json>',
    );
    exitCode = 64;
    return;
  }

  _requireSha256(
    arguments[0],
    '329689763b651096989bd8260b643731083fc5fd17f6bd7834d158713f738cbd',
  );
  _requireSha256(
    arguments[1],
    '3c25698e94d5199c75b784cc361cda9c6775389eb61f8f4fb05fde1a757ae3f9',
  );
  const sourceHashes = <String, String>{
    'src/parser.y': '803aa7c0b1acba2228e52d1de392fb51e60a7bbe23e42870aea1d62c43360c60',
    'src/lexer.l': 'cfb3af17a786df30d7e30dae5861b84747d4904f8ce7ae9ab9b48bde342ee7f3',
    'src/builtin.jq': 'b8a5fd9579be9b51c9a04e6620f8c1655539aa57eea33a84e202a8dea401f2a4',
    'src/builtin.c': '0a29617dbf74a6fdabf644f5da82269113fef69bb46efaa3b232515d90305342',
    'src/libm.h': '13aaee9c9537fdd2acf1105f3bc7de86b953ae4a77bd7a04b07d2ad84ea7e95d',
  };
  for (final entry in sourceHashes.entries) {
    _requireSha256(
      '.dart_tool/reference/jq-1.8.2/${entry.key}',
      entry.value,
    );
  }

  final cases = <Map<String, Object?>>[];
  for (final path in arguments.take(2)) {
    final sourceName = path.split(RegExp(r'[/\\]')).last;
    final source = File(path).readAsStringSync();
    for (final fixture in parseFixtures(source, source: sourceName)) {
      cases.add(classifyFixture(fixture));
    }
  }
  cases.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  final ids = cases.map((fixture) => fixture['id']).toSet();
  if (cases.length != 781 || ids.length != 781) {
    throw StateError(
      'Expected 781 unique active IDs; found ${cases.length} rows and ${ids.length} IDs.',
    );
  }
  final report = <String, Object?>{
    'format': 'zaru-reference-classification-v1',
    'upstream': <String, Object?>{
      'tag': 'jq-1.8.2',
      'commit': '34f7186b86743a083a589741b6cea95293524108',
      'parser': 'src/parser.y',
      'lexer': 'src/lexer.l',
      'jqBuiltins': 'src/builtin.jq',
      'nativeBuiltins': 'src/builtin.c',
      'mathBuiltins': 'src/libm.h',
      'archiveSha256': '332dd9ae07c19fb47f6e8c4dd973a141064c0d35363c254235ee84d2d9e0167c',
      'sourceSha256': <String, String>{
        'src/parser.y': '803aa7c0b1acba2228e52d1de392fb51e60a7bbe23e42870aea1d62c43360c60',
        'src/lexer.l': 'cfb3af17a786df30d7e30dae5861b84747d4904f8ce7ae9ab9b48bde342ee7f3',
        'src/builtin.jq': 'b8a5fd9579be9b51c9a04e6620f8c1655539aa57eea33a84e202a8dea401f2a4',
        'src/builtin.c': '0a29617dbf74a6fdabf644f5da82269113fef69bb46efaa3b232515d90305342',
        'src/libm.h': '13aaee9c9537fdd2acf1105f3bc7de86b953ae4a77bd7a04b07d2ad84ea7e95d',
      },
      'sourceRanges': <String, String>{
        'src/parser.y': '199-963',
        'src/lexer.l': '1-154',
        'src/builtin.jq': '1-260',
        'src/builtin.c': '1974-2138',
        'src/libm.h': '1-300',
      },
    },
    'total': cases.length,
    'files': <String, int>{'jq.test': 550, 'man.test': 231},
    'fixtureSha256': <String, String>{
      'jq.test': '329689763b651096989bd8260b643731083fc5fd17f6bd7834d158713f738cbd',
      'man.test': '3c25698e94d5199c75b784cc361cda9c6775389eb61f8f4fb05fde1a757ae3f9',
    },
    'classificationMethod':
        'Source-only token scan against pinned grammar and builtin registries; no jq or zaru execution.',
    'cases': cases,
  };
  Directory(File(arguments[2]).parent.path).createSync(recursive: true);
  File(arguments[2]).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
}

Map<String, Object?> classifyFixture(JqFixture fixture) => _classify(fixture);

Map<String, Object?> _classify(JqFixture fixture) {
  final lexer = _SourceScanner(fixture.program);
  final tokens = lexer.scan();
  final declaredNames = <String>{};
  final definedFunctions = <String>{};
  final functionDefinitions = <_FunctionDefinition>[];
  final scopedCallableParameters = <_ScopedCallableParameter>[];
  final scopedBindings = <_ScopedBinding>[];
  final declarationTokenIndexes = <int>{};
  final moduleAliasTokenIndexes = <int>{};
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.text == 'as') {
      final pattern = _readPattern(tokens, i + 1);
      if (pattern != null) {
        final patternNames = <String>{...pattern.names};
        declarationTokenIndexes.addAll(pattern.tokenIndexes);
        var end = pattern.endIndex;
        while (end < tokens.length && tokens[end].text == '?//') {
          final alternative = _readPattern(tokens, end + 1);
          if (alternative == null) break;
          patternNames.addAll(alternative.names);
          declarationTokenIndexes.addAll(alternative.tokenIndexes);
          end = alternative.endIndex;
        }
        declaredNames.addAll(patternNames);
        final start = _bindingScopeStart(tokens, end);
        final scopeEnd = _bindingScopeEnd(tokens, i);
        for (final name in patternNames) {
          scopedBindings.add(_ScopedBinding(name, start, scopeEnd));
        }
        i = end - 1;
      }
    } else if (token.text == 'label' &&
        i + 1 < tokens.length &&
        tokens[i + 1].kind == 'binding') {
      final name = tokens[i + 1].text;
      declaredNames.add(name);
      declarationTokenIndexes.add(i + 1);
      final start = i + 2 < tokens.length && tokens[i + 2].text == '|'
          ? i + 3
          : i + 2;
      scopedBindings.add(
        _ScopedBinding(name, start, _bindingScopeEnd(tokens, i)),
      );
    }

    if (token.kind == 'identifier' &&
        i > 0 &&
        tokens[i - 1].text == 'def') {
      declaredNames.add(token.text);
      definedFunctions.add(token.text);
      final colon = _definitionColon(tokens, i + 1);
      if (colon != null) {
        final scopeEnd = _definitionEnd(tokens, colon + 1);
        functionDefinitions.add(
          _FunctionDefinition(
            token.text,
            _definitionArity(tokens, i + 1, colon),
            i - 1,
            colon + 1,
            scopeEnd,
          ),
        );
        for (var parameter = i + 1; parameter < colon; parameter++) {
          if (tokens[parameter].kind == 'binding') {
            final name = tokens[parameter].text;
            declaredNames.add(name);
            declarationTokenIndexes.add(parameter);
            scopedBindings.add(_ScopedBinding(name, colon + 1, scopeEnd));
          } else if (tokens[parameter].kind == 'identifier' &&
              !_isKeyword(tokens[parameter].text)) {
            declaredNames.add(tokens[parameter].text);
            scopedCallableParameters.add(
              _ScopedCallableParameter(
                tokens[parameter].text,
                colon + 1,
                scopeEnd,
              ),
            );
          }
        }
      }
    } else if (token.kind == 'identifier' &&
        i > 0 &&
        tokens[i - 1].text == 'as') {
      declaredNames.add(token.text);
      moduleAliasTokenIndexes.add(i);
    }
  }

  final reachableTokenIndexes = _reachableFilterTokens(
    tokens,
    functionDefinitions,
  );
  final objectKeyIndexes = _objectKeyIndexes(tokens);
  final names = <String>{};
  final bindings = <String>{};
  final objectKeys = <String>{};
  final forms = <String>{};
  final builtinCallArities = <String, Set<int>>{};
  final implicitBuiltinCalls = <String>{};
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final isObjectKey = objectKeyIndexes.contains(i);
    if (token.kind == 'identifier') {
      if (isObjectKey) {
        objectKeys.add(token.text);
      } else if (reachableTokenIndexes.contains(i) &&
          !moduleAliasTokenIndexes.contains(i) &&
          !scopedCallableParameters.any(
            (parameter) =>
                parameter.name == token.text &&
                i >= parameter.startToken &&
                i < parameter.endToken,
          ) &&
          !_isKeyword(token.text)) {
        names.add(token.text);
        if (_isBuiltinName(token.text)) {
          builtinCallArities
              .putIfAbsent(token.text, () => <int>{})
              .add(_callArity(tokens, i));
        }
      }
    }
    if (token.kind == 'binding') {
      bindings.add(token.text);
      names.add(r'$' + token.text);
    }
    if (token.kind == 'field') forms.add('field-access');
    if (token.kind == 'number') forms.add('number-literal');
    if (token.kind == 'string') forms.add('string-literal');
    if (token.kind == 'string' && token.text == r'\(') {
      forms.add('interpolation');
      if (reachableTokenIndexes.contains(i)) {
        names.add('format');
        names.add('tostring');
        implicitBuiltinCalls.add('format');
        implicitBuiltinCalls.add('tostring');
        builtinCallArities.putIfAbsent('tostring', () => <int>{}).add(0);
      }
    }
    if (token.kind == 'format') forms.add('@format');
    if (token.kind == 'loc') forms.add(r'$__loc__');
    if (_supportedForms.contains(token.text)) forms.add(token.text);
    if (token.text == '..' && reachableTokenIndexes.contains(i)) {
      forms.add('recursive-descent');
      names.add('recurse');
      builtinCallArities.putIfAbsent('recurse', () => <int>{}).add(0);
    }
    if (!isObjectKey && token.text == '=') forms.add('assignment');
    if (!isObjectKey && _deferredForms.contains(token.text)) {
      forms.add(token.text);
    }
    if (token.text == '[' || token.text == '{' || token.text == '(') {
      forms.add(token.text == '['
          ? 'array/index/iteration/slice'
          : token.text == '{'
          ? 'object-construction/pattern'
          : 'grouping/call');
    }
  }
  final deferred = forms.intersection(_deferredForms).toList()..sort();
  final builtins = <Map<String, Object?>>[];
  final unknown = <String>[];
  for (final name in names) {
    if (definedFunctions.contains(name) || name.startsWith(r'$')) continue;
    final origins = <String>[
      if (_jqDefinedNames.contains(name)) 'src/builtin.jq',
      if (_nativeNames.contains(name)) 'src/builtin.c function_list',
      if (_mathNames.contains(name)) 'src/libm.h',
      if (_bytecodedNames.contains(name)) 'src/builtin.c bytecoded definitions',
      if (_builtinListNames.contains(name)) 'src/builtin.c gen_builtin_list',
    ];
    if (origins.isEmpty && !_isKeyword(name)) {
      unknown.add(name);
      continue;
    }
    if (origins.isEmpty) continue;
    final arities = builtinCallArities[name] ?? <int>{};
    final overloads = <Map<String, Object?>>[];
    var allM1 = arities.isNotEmpty || implicitBuiltinCalls.contains(name);
    final dependencies = <String>{};
    for (final arity in arities.toList()..sort()) {
      final key = '$name/$arity';
      final isM1 = _m1JqOverloads.contains(key) ||
          _m1NativeOverloads.contains(key) ||
          _m1BytecodedOverloads.contains(key);
      if (!isM1) allM1 = false;
      final overloadDependencies = _m1OverloadDependencies[key] ?? const <String>[];
      dependencies.addAll(overloadDependencies);
      overloads.add(<String, Object?>{
        'arity': arity,
        'classification': isM1 ? 'M1-candidate' : 'deferred-builtin',
        'source': _overloadSource(name, arity),
        'dependencies': overloadDependencies,
      });
    }
    if (implicitBuiltinCalls.contains(name)) {
      if (name == 'format') {
        dependencies.add('tostring/0');
        overloads.add(<String, Object?>{
          'kind': 'implicit-text-format',
          'classification': 'M1-candidate',
          'source': 'src/parser.y interpolation lowering',
          'dependencies': <String>['tostring/0'],
        });
      }
      if (name == 'tostring') {
        overloads.add(<String, Object?>{
          'kind': 'implicit-format-conversion',
          'classification': 'M1-candidate',
          'source': 'src/builtin.c f_format',
          'dependencies': const <String>[],
        });
      }
    }
    if (origins.contains('src/libm.h')) allM1 = false;
    final classification = allM1
        ? 'M1-candidate'
        : origins.contains('src/libm.h')
        ? 'deferred-platform-build-dependent'
        : 'deferred-builtin';
    builtins.add(<String, Object?>{
      'name': name,
      'origin': origins.join('; '),
      'callArities': arities.toList()..sort(),
      'overloads': overloads,
      'dependencies': dependencies.toList()..sort(),
      'm1': classification,
    });
  }
  builtins.sort(
    (a, b) => (a['name']! as String).compareTo(b['name']! as String),
  );
  unknown.sort();
  forms.removeWhere((form) => form == ' ' || form.isEmpty);
  final hasDeferredBuiltin =
      builtins.any((builtin) => (builtin['m1']! as String).startsWith('deferred-'));
  final moduleSyntaxPresent = forms.any(
    const <String>{'import', 'include', 'module'}.contains,
  );
  final moduleNames = unknown
      .where((name) => moduleSyntaxPresent || name.contains('::'))
      .toList()
    ..sort();
  final unknownCoreNames =
      unknown.where((name) => !moduleNames.contains(name)).toList()..sort();
  final specialBindings = bindings
      .where(_deferredSpecialBindings.contains)
      .toList()
    ..sort();
  final moduleBindingNames =
      bindings.where((binding) => binding.contains('::')).toList()..sort();
  final unboundVariables = <String>{};
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.kind != 'binding' ||
        declarationTokenIndexes.contains(i) ||
        _deferredSpecialBindings.contains(token.text) ||
        token.text.contains('::')) {
      continue;
    }
    final isBound = scopedBindings.any(
      (binding) =>
          binding.name == token.text &&
          i >= binding.startToken &&
          i < binding.endToken,
    );
    if (!isBound) unboundVariables.add(token.text);
  }
  final unboundCoreVariables = unboundVariables.toList()..sort();
  final status =
      deferred.isNotEmpty || hasDeferredBuiltin || specialBindings.isNotEmpty
      ? 'explicit-deferred-dependency'
      : unknownCoreNames.isNotEmpty || unboundCoreVariables.isNotEmpty
      ? 'core-undefined-name-diagnostic'
      : 'M1-core-candidate';
  return <String, Object?>{
    'id': fixture.id,
    'kind': fixture.kind.name,
    'classification': status,
    'forms': forms.toList()..sort(),
    'builtins': builtins,
    'sourceNames': names.toList()..sort(),
    'unknownCoreNames': unknownCoreNames,
    'moduleDependencyNames': moduleNames,
    'moduleBindingNames': moduleBindingNames,
    'bindings': bindings.toList()..sort(),
    'unboundCoreVariables': unboundCoreVariables,
    'deferredSpecialBindings': specialBindings,
    'declaredNames': declaredNames.toList()..sort(),
    'scopeBindings': scopedBindings
        .map(
          (binding) => <String, Object>{
            'name': binding.name,
            'fromToken': binding.startToken,
            'untilToken': binding.endToken,
          },
        )
        .toList(),
    'objectKeys': objectKeys.toList()..sort(),
    'sourceEvidence': <String, Object?>{
      'program': fixture.program,
      'programLine': fixture.line,
      'origin': fixture.origin.name,
    },
  };
}

final class _PatternBindings {
  const _PatternBindings(this.names, this.tokenIndexes, this.endIndex);

  final Set<String> names;
  final Set<int> tokenIndexes;
  final int endIndex;
}

_PatternBindings? _readPattern(List<_Token> tokens, int start) {
  if (start >= tokens.length) return null;
  if (tokens[start].kind == 'binding') {
    return _PatternBindings(
      <String>{tokens[start].text},
      <int>{start},
      start + 1,
    );
  }
  if (tokens[start].text != '[' && tokens[start].text != '{') return null;
  final stack = <String>[];
  final names = <String>{};
  final tokenIndexes = <int>{};
  for (var i = start; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (tokens[i].kind == 'binding' && stack.isNotEmpty) {
      names.add(tokens[i].text);
      tokenIndexes.add(i);
    }
    if (text == '[') {
      stack.add(']');
    } else if (text == '{') {
      stack.add('}');
    } else if (text == '(') {
      stack.add(')');
    } else if (stack.isNotEmpty && text == stack.last) {
      stack.removeLast();
      if (stack.isEmpty) {
        return _PatternBindings(names, tokenIndexes, i + 1);
      }
    }
  }
  return null;
}

int _bindingScopeStart(List<_Token> tokens, int patternEnd) {
  if (patternEnd < tokens.length && tokens[patternEnd].text == '|') {
    return patternEnd + 1;
  }
  if (patternEnd < tokens.length && tokens[patternEnd].text == '(') {
    var depth = 1;
    for (var i = patternEnd + 1; i < tokens.length; i++) {
      if (tokens[i].text == '(') depth++;
      if (tokens[i].text == ')') depth--;
      if (tokens[i].text == ';' && depth == 1) return i + 1;
      if (depth == 0) break;
    }
  }
  return patternEnd;
}

int _bindingScopeEnd(List<_Token> tokens, int declarationIndex) {
  final functionEnd = _containingFunctionEnd(tokens, declarationIndex);
  if (functionEnd != null) return functionEnd;
  final delimiterEnd = _containingDelimiterEnd(tokens, declarationIndex);
  return delimiterEnd ?? tokens.length;
}

int? _containingFunctionEnd(List<_Token> tokens, int position) {
  int? result;
  for (var i = 0; i < position; i++) {
    if (tokens[i].text != 'def' ||
        i + 1 >= tokens.length ||
        tokens[i + 1].kind != 'identifier') {
      continue;
    }
    final colon = _definitionColon(tokens, i + 2);
    if (colon == null || colon >= position) continue;
    final end = _definitionEnd(tokens, colon + 1);
    if (end > position && (result == null || end < result)) result = end;
  }
  return result;
}

int? _containingDelimiterEnd(List<_Token> tokens, int position) {
  final stack = <(String, int)>[];
  for (var i = 0; i < position; i++) {
    final closing = switch (tokens[i].text) {
      '(' => ')',
      '[' => ']',
      '{' => '}',
      _ => null,
    };
    if (closing != null) {
      stack.add((closing, i));
    } else if (stack.isNotEmpty && tokens[i].text == stack.last.$1) {
      stack.removeLast();
    }
  }
  if (stack.isEmpty) return null;
  final (closing, _) = stack.last;
  var depth = 1;
  for (var i = position; i < tokens.length; i++) {
    if (tokens[i].text == closing) {
      depth--;
      if (depth == 0) return i;
    } else if (tokens[i].text == '(' ||
        tokens[i].text == '[' ||
        tokens[i].text == '{') {
      final matching = tokens[i].text == '('
          ? ')'
          : tokens[i].text == '['
          ? ']'
          : '}';
      if (matching == closing) depth++;
    }
  }
  return tokens.length;
}

int? _definitionColon(List<_Token> tokens, int start) {
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  for (var i = start; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (text == ':' && parens == 0 && brackets == 0 && braces == 0) {
      return i;
    }
    if (text == ';' && parens == 0 && brackets == 0 && braces == 0) {
      return null;
    }
    if (text == '(') {
      parens++;
    } else if (text == ')') {
      parens--;
    } else if (text == '[') {
      brackets++;
    } else if (text == ']') {
      brackets--;
    } else if (text == '{') {
      braces++;
    } else if (text == '}') {
      braces--;
    }
  }
  return null;
}

int _definitionArity(List<_Token> tokens, int start, int colon) {
  var open = start;
  while (open < colon && tokens[open].text != '(') {
    open++;
  }
  if (open == colon) return 0;
  var arity = 1;
  var hasParameter = false;
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  for (var i = open + 1; i < colon; i++) {
    final text = tokens[i].text;
    if (text == ')' && parens == 0 && brackets == 0 && braces == 0) {
      return hasParameter ? arity : 0;
    }
    if (text == ';' && parens == 0 && brackets == 0 && braces == 0) {
      arity++;
      hasParameter = false;
      continue;
    }
    if (text != ',' && text != ';') hasParameter = true;
    if (text == '(') {
      parens++;
    } else if (text == ')') {
      parens--;
    } else if (text == '[') {
      brackets++;
    } else if (text == ']') {
      brackets--;
    } else if (text == '{') {
      braces++;
    } else if (text == '}') {
      braces--;
    }
  }
  return hasParameter ? arity : 0;
}

int _callArity(List<_Token> tokens, int nameIndex) {
  if (nameIndex + 1 >= tokens.length ||
      tokens[nameIndex + 1].text != '(') {
    return 0;
  }
  var arity = 1;
  var hasArgument = false;
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  for (var i = nameIndex + 2; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (text == ')' && parens == 0 && brackets == 0 && braces == 0) {
      return hasArgument ? arity : 0;
    }
    if (text == ';' && parens == 0 && brackets == 0 && braces == 0) {
      arity++;
      hasArgument = false;
      continue;
    }
    if (text != ',' && text != ';') hasArgument = true;
    if (text == '(') {
      parens++;
    } else if (text == ')') {
      parens--;
    } else if (text == '[') {
      brackets++;
    } else if (text == ']') {
      brackets--;
    } else if (text == '{') {
      braces++;
    } else if (text == '}') {
      braces--;
    }
  }
  return hasArgument ? arity : 0;
}

Set<int> _objectKeyIndexes(List<_Token> tokens) {
  final result = <int>{};
  var braceDepth = 0;
  for (var i = 0; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (text == '}') {
      braceDepth--;
      continue;
    }
    if (braceDepth > 0 &&
        tokens[i].kind == 'identifier' &&
        (i + 1 < tokens.length && tokens[i + 1].text == ':')) {
      result.add(i);
    } else if (braceDepth > 0 &&
        tokens[i].kind == 'identifier' &&
        (i + 1 < tokens.length &&
            (tokens[i + 1].text == ',' || tokens[i + 1].text == '}')) &&
        (i == 0 ||
            tokens[i - 1].text == '{' ||
            tokens[i - 1].text == ',')) {
      result.add(i);
    }
    if (text == '{') braceDepth++;
  }
  return result;
}

bool _isBuiltinName(String name) =>
    _jqDefinedNames.contains(name) ||
    _nativeNames.contains(name) ||
    _mathNames.contains(name) ||
    _bytecodedNames.contains(name) ||
    _builtinListNames.contains(name);

String _overloadSource(String name, int arity) {
  final key = '$name/$arity';
  if (_m1JqOverloads.contains(key)) return 'src/builtin.jq';
  if (_m1NativeOverloads.contains(key)) return 'src/builtin.c function_list';
  if (_m1BytecodedOverloads.contains(key)) {
    return 'src/builtin.c bytecoded definitions';
  }
  if (_mathNames.contains(name)) return 'src/libm.h';
  if (_jqDefinedNames.contains(name)) return 'src/builtin.jq';
  if (_nativeNames.contains(name)) return 'src/builtin.c function_list';
  if (_bytecodedNames.contains(name)) {
    return 'src/builtin.c bytecoded definitions';
  }
  return 'src/builtin.c gen_builtin_list';
}

Set<int> _reachableFilterTokens(
  List<_Token> tokens,
  List<_FunctionDefinition> definitions,
) {
  final reachable = <int>{};
  final reachableDefinitions = <_FunctionDefinition>{};
  final queue = <_FunctionDefinition>[];

  bool isInDefinition(int index, {_FunctionDefinition? except}) =>
      definitions.any(
        (definition) =>
            !identical(definition, except) &&
            (except == null || definition.sourceStart >= except.bodyStart) &&
            index >= definition.sourceStart &&
            index <= definition.endToken,
      );

  void discoverCalls(int start, int end, {_FunctionDefinition? owner}) {
    for (var i = start; i < end; i++) {
      if (isInDefinition(i, except: owner)) continue;
      final token = tokens[i];
      if (token.kind != 'identifier') continue;
      final arity = _callArity(tokens, i);
      for (final definition in definitions) {
        if (definition.name == token.text && definition.arity == arity) {
          if (reachableDefinitions.add(definition)) {
            queue.add(definition);
          }
        }
      }
    }
  }

  for (var i = 0; i < tokens.length; i++) {
    if (!isInDefinition(i)) reachable.add(i);
  }
  discoverCalls(0, tokens.length);
  for (var cursor = 0; cursor < queue.length; cursor++) {
    final definition = queue[cursor];
    for (var i = definition.bodyStart; i < definition.endToken; i++) {
      if (!isInDefinition(i, except: definition)) reachable.add(i);
    }
    discoverCalls(
      definition.bodyStart,
      definition.endToken,
      owner: definition,
    );
  }
  return reachable;
}

int _definitionEnd(List<_Token> tokens, int start) {
  var parens = 0;
  var brackets = 0;
  var braces = 0;
  var nestedDefinitions = 0;
  for (var i = start; i < tokens.length; i++) {
    final text = tokens[i].text;
    if (text == '(') {
      parens++;
    } else if (text == ')') {
      parens--;
    } else if (text == '[') {
      brackets++;
    } else if (text == ']') {
      brackets--;
    } else if (text == '{') {
      braces++;
    } else if (text == '}') {
      braces--;
    } else if (parens == 0 && brackets == 0 && braces == 0 && text == 'def') {
      nestedDefinitions++;
    } else if (text == ';' &&
        parens == 0 &&
        brackets == 0 &&
        braces == 0) {
      if (nestedDefinitions > 0) {
        nestedDefinitions--;
      } else {
        return i;
      }
    }
  }
  return tokens.length;
}

final class _ScopedBinding {
  const _ScopedBinding(this.name, this.startToken, this.endToken);

  final String name;
  final int startToken;
  final int endToken;
}

final class _ScopedCallableParameter {
  const _ScopedCallableParameter(this.name, this.startToken, this.endToken);

  final String name;
  final int startToken;
  final int endToken;
}

final class _FunctionDefinition {
  const _FunctionDefinition(
    this.name,
    this.arity,
    this.sourceStart,
    this.bodyStart,
    this.endToken,
  );

  final String name;
  final int arity;
  final int sourceStart;
  final int bodyStart;
  final int endToken;
}

bool _isKeyword(String name) => const <String>{
  'as', 'import', 'include', 'module', 'def', 'if', 'then', 'else', 'elif',
  'and', 'or', 'end', 'reduce', 'foreach', 'try', 'catch', 'label', 'break',
  'true', 'false', 'null',
}.contains(name);

final class _Token {
  const _Token(this.kind, this.text);
  final String kind;
  final String text;
}

final class _SourceScanner {
  _SourceScanner(this.source);
  final String source;
  final List<_Token> _tokens = <_Token>[];
  var _offset = 0;

  List<_Token> scan() {
    _scanUntil(null);
    return _tokens;
  }

  void _scanUntil(int? closingParen) {
    var nestedParentheses = 0;
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset);
      if (closingParen != null && code == closingParen) {
        if (nestedParentheses == 0) {
          _offset++;
          return;
        }
        nestedParentheses--;
        _tokens.add(const _Token('punctuation', ')'));
        _offset++;
        continue;
      }
      if (closingParen != null && code == 40) {
        nestedParentheses++;
        _tokens.add(const _Token('punctuation', '('));
        _offset++;
        continue;
      }
      if (code == 32 || code == 9 || code == 10 || code == 13) {
        _offset++;
        continue;
      }
      if (code == 35) {
        while (_offset < source.length && source.codeUnitAt(_offset) != 10) {
          _offset++;
        }
        continue;
      }
      if (code == 34) {
        _scanString();
        continue;
      }
      if (code == 64 && _offset + 1 < source.length && _isIdentifierStart(source.codeUnitAt(_offset + 1))) {
        _offset++;
        final start = _offset;
        _scanIdentifier();
        _tokens.add(_Token('format', '@${source.substring(start, _offset)}'));
        continue;
      }
      if (code == 36) {
        _scanBinding();
        continue;
      }
      if (_isDigit(code) ||
          (code == 46 &&
              _offset + 1 < source.length &&
              _isDigit(source.codeUnitAt(_offset + 1)))) {
        final start = _offset;
        _scanNumber();
        _tokens.add(_Token('number', source.substring(start, _offset)));
        continue;
      }
      if (code == 46 && _offset + 1 < source.length && _isIdentifierStart(source.codeUnitAt(_offset + 1))) {
        _offset++;
        _scanIdentifier();
        _tokens.add(const _Token('field', 'field-access'));
        continue;
      }
      if (_isIdentifierStart(code)) {
        final start = _offset;
        _scanIdentifier();
        final word = source.substring(start, _offset);
        if (word == r'$__loc__') {
          _tokens.add(_Token('loc', word));
        } else {
          _tokens.add(_Token('identifier', word));
        }
        continue;
      }
      final operator = _longestOperator();
      if (operator != null) {
        _tokens.add(_Token('operator', operator));
        _offset += operator.length;
        continue;
      }
      final char = String.fromCharCode(code);
      _tokens.add(_Token('punctuation', char));
      _offset++;
    }
  }

  void _scanString() {
    _offset++;
    _tokens.add(const _Token('string', '"'));
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset++);
      if (code == 92) {
        if (_offset < source.length && source.codeUnitAt(_offset) == 40) {
          _offset++;
          _tokens.add(const _Token('string', r'\('));
          _scanUntil(41);
          continue;
        }
        if (_offset < source.length) _offset++;
        continue;
      }
      if (code == 34) return;
    }
  }

  void _scanBinding() {
    _offset++;
    if (_offset < source.length && source.codeUnitAt(_offset) == 95 &&
        source.startsWith('__loc__', _offset)) {
      _offset += 7;
      _tokens.add(const _Token('loc', r'$__loc__'));
      return;
    }
    var depth = 0;
    while (_offset < source.length && source.codeUnitAt(_offset) == 36) {
      depth++;
      _offset++;
    }
    final start = _offset;
    if (_offset < source.length && _isIdentifierStart(source.codeUnitAt(_offset))) {
      _scanIdentifier();
      final name = source.substring(start, _offset);
      _tokens.add(_Token('binding', depth == 0 ? name : '__literal:$name'));
    } else {
      _tokens.add(const _Token('punctuation', r'$'));
    }
  }

  void _scanNumber() {
    if (source.codeUnitAt(_offset) == 46) {
      _offset++;
      while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
        _offset++;
      }
    } else {
      while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
        _offset++;
      }
      if (_offset < source.length && source.codeUnitAt(_offset) == 46) {
        _offset++;
        while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
          _offset++;
        }
      }
    }
    if (_offset < source.length &&
        (source.codeUnitAt(_offset) == 69 || source.codeUnitAt(_offset) == 101)) {
      var exponentEnd = _offset + 1;
      if (exponentEnd < source.length &&
          (source.codeUnitAt(exponentEnd) == 43 ||
              source.codeUnitAt(exponentEnd) == 45)) {
        exponentEnd++;
      }
      final exponentStart = exponentEnd;
      while (exponentEnd < source.length && _isDigit(source.codeUnitAt(exponentEnd))) {
        exponentEnd++;
      }
      if (exponentEnd > exponentStart) _offset = exponentEnd;
    }
  }

  void _scanIdentifier() {
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset);
      if (_isIdentifierPart(code)) {
        _offset++;
      } else if (code == 58 && _offset + 1 < source.length && source.codeUnitAt(_offset + 1) == 58) {
        _offset += 2;
      } else {
        break;
      }
    }
  }

  String? _longestOperator() {
    for (final operator in const <String>[
      '//=', '?//', '|=', '+=', '-=', '*=', '/=', '%=', '!=', '==', '//',
      '<=', '>=', '..',
    ]) {
      if (source.startsWith(operator, _offset)) return operator;
    }
    return null;
  }

  static bool _isIdentifierStart(int code) =>
      (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
  static bool _isIdentifierPart(int code) =>
      _isIdentifierStart(code) || (code >= 48 && code <= 57);
  static bool _isDigit(int code) => code >= 48 && code <= 57;
}
