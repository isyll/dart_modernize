library;

export 'src/cli/config.dart' show DartModernizeConfig, readDartModernizeConfig;
export 'src/cli/options.dart'
    show
        CliOptions,
        buildArgParser,
        defaultOffTransformations,
        resolveTargetPath,
        transformationNames;
export 'src/engine/edit_collector.dart';
export 'src/engine/source_edit.dart';
export 'src/engine/text_shape.dart' show LineEndings;
export 'src/modernize_exception.dart';
export 'src/pipeline/transformation.dart';
export 'src/runner.dart';
