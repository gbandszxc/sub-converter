import '../ass/ass_dialect.dart';
import '../ass/ass_parser.dart';

/// SSA (SubStation Alpha) parser.
///
/// Thin wrapper: all logic lives in the dialect-parameterised [AssParser] in
/// `lib/formats/ass/`. This subclass only fixes the dialect to
/// [AssDialect.ssa], so SSA and ASS can never diverge.
class SsaParser extends AssParser {
  SsaParser() : super(AssDialect.ssa);
}
