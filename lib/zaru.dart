/// A pure-Dart jq engine for the Dart VM and browsers.
///
/// [Zaru.compile] turns jq source into a reusable [ZaruFilter]; its `run` and
/// `runJson` methods return lazy result streams. This release evaluates a core
/// subset of jq (identity, access, construction, operators, `//`, `if`,
/// `try`/`catch`, interpolation, `as $x` bindings and external variables);
/// everything else fails to compile with a [ZaruCompileError] whose
/// `isUnsupported` is set. See `docs/api.md` for the exact surface.
library;

export 'src/errors.dart'
    show ZaruCompileError, ZaruMissingArgumentError, ZaruRuntimeError;
export 'src/filter.dart' show ZaruFilter;
export 'src/number.dart' show ZaruNumber;
export 'src/zaru.dart' show Zaru;
