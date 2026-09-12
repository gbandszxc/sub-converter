import '../ass/ass_dialect.dart';
import '../ass/ass_writer.dart';

/// SSA (SubStation Alpha) writer.
///
/// Thin wrapper: all logic lives in the dialect-parameterised [AssWriter] in
/// `lib/formats/ass/`. This subclass only fixes the dialect to
/// [AssDialect.ssa], so SSA and ASS can never diverge.
class SsaWriter extends AssWriter {
  SsaWriter() : super(AssDialect.ssa);
}
