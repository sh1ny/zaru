/// A pure-Dart jq engine for the Dart VM and browsers.
///
/// [Zaru.compile] turns jq source into a reusable [ZaruFilter]; its `run` and
/// `runJson` methods return lazy result streams. This release evaluates the jq
/// core language (access, construction, operators, `//`, `if`, `try`/`catch`,
/// interpolation, bindings with destructuring, `def`, `reduce`, `foreach`,
/// `label`/`break`, `..` and external variables) and the M1 helpers (`select`,
/// `recurse`, `range`, `while`, `until`, `repeat`, `limit`, `skip`, `first`,
/// `last`, `nth`, `tostring`, `empty`, `error`, `not`); everything else fails
/// to compile with a [ZaruCompileError] whose `isUnsupported` is set. See
/// `docs/api.md` for the exact surface.
library;

export 'src/errors.dart'
    show ZaruCompileError, ZaruMissingArgumentError, ZaruRuntimeError;
export 'src/filter.dart' show ZaruFilter;
export 'src/number.dart' show ZaruNumber;
export 'src/zaru.dart' show Zaru;
