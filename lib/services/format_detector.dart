import '../formats/format_registry.dart';
import '../models/format_descriptor.dart';
import '../models/format_signature.dart';
import '../models/subtitle_format.dart';

/// Best guess at a file's format, with the evidence that produced it.
class FormatDetection {
  const FormatDetection({
    required this.format,
    required this.score,
    required this.evidence,
    required this.extensionMatched,
    this.runnerUp,
    this.runnerUpScore = 0,
  });

  const FormatDetection.none()
      : format = null,
        score = 0,
        evidence = const <String>[],
        extensionMatched = false,
        runnerUp = null,
        runnerUpScore = 0;

  /// Detected format, or `null` when nothing matched.
  final SubtitleFormat? format;

  /// Winning score, including the extension bonus.
  final int score;

  /// Signature ids that fired for [format], for logging and tests.
  final List<String> evidence;

  /// Whether the file name's extension also pointed at [format].
  final bool extensionMatched;

  /// Second best candidate, when there was one.
  final SubtitleFormat? runnerUp;

  final int runnerUpScore;

  bool get isDetected => format != null;

  /// True when the content alone identified the format (not just the name).
  bool get isContentBased => evidence.isNotEmpty;

  /// True when the runner-up scored as high as the winner.
  bool get isAmbiguous =>
      runnerUp != null && runnerUpScore == score && score > 0;

  @override
  String toString() => 'FormatDetection(${format?.label ?? 'none'}, '
      'score: $score, evidence: $evidence)';
}

/// Identifies a subtitle format from its content, corroborated by its file
/// name.
///
/// Content dominates: a `.ass` file containing SubRip timing lines is detected
/// as SRT. The extension only adds a bonus, so a mislabelled file still
/// converts, and it decides the outcome when the content is inconclusive.
class FormatDetector {
  FormatDetector(this.registry);

  /// Bonus added when the file name's extension matches a candidate.
  ///
  /// Lower than the weakest structural signature (60) so content always wins,
  /// but higher than nothing so a tie breaks towards the declared extension.
  static const int extensionBonus = 30;

  final FormatRegistry registry;

  /// Detects the format of [content].
  ///
  /// [fileName] is optional; pass the source file name so its extension can
  /// corroborate the content.
  FormatDetection detect(String content, {String? fileName}) {
    final List<_ScoredFormat> scored = <_ScoredFormat>[];
    final List<FormatDescriptor> descriptors = registry.descriptors;
    for (int index = 0; index < descriptors.length; index++) {
      final FormatDescriptor descriptor = descriptors[index];
      final List<String> evidence = <String>[];
      int score = 0;
      for (final FormatSignature signature in descriptor.signatures) {
        if (signature.matches(content)) {
          score += signature.weight;
          evidence.add(signature.id);
        }
      }
      final bool extensionMatched =
          fileName != null && descriptor.matchesExtension(fileName);
      if (extensionMatched) {
        score += extensionBonus;
      }
      scored.add(
        _ScoredFormat(
          descriptor.format,
          score,
          evidence,
          extensionMatched,
          index,
        ),
      );
    }

    scored.sort(_compare);

    final _ScoredFormat best = scored.first;
    final _ScoredFormat? second = scored.length > 1 ? scored[1] : null;

    if (best.score <= 0) {
      return const FormatDetection.none();
    }
    return FormatDetection(
      format: best.format,
      score: best.score,
      evidence: best.evidence,
      extensionMatched: best.extensionMatched,
      runnerUp: second != null && second.score > 0 ? second.format : null,
      runnerUpScore: second?.score ?? 0,
    );
  }

  /// Orders candidates by score, then by extension match, then by content
  /// evidence, then by registration order so detection is deterministic.
  static int _compare(_ScoredFormat a, _ScoredFormat b) {
    if (a.score != b.score) {
      return b.score - a.score;
    }
    if (a.extensionMatched != b.extensionMatched) {
      return a.extensionMatched ? -1 : 1;
    }
    if (a.evidence.length != b.evidence.length) {
      return b.evidence.length - a.evidence.length;
    }
    return a.order - b.order;
  }
}

class _ScoredFormat {
  const _ScoredFormat(
    this.format,
    this.score,
    this.evidence,
    this.extensionMatched,
    this.order,
  );

  final SubtitleFormat format;
  final int score;
  final List<String> evidence;
  final bool extensionMatched;
  final int order;
}
