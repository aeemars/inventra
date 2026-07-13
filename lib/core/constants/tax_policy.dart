/// Nigeria Tax Act, 2025 (effective Jan 1, 2026) — small company classification.
/// A company with annual gross turnover at or below this figure, and fixed
/// assets not exceeding ₦250,000,000, is exempt from Companies Income Tax,
/// Capital Gains Tax, and the Development Levy. Above this threshold, the
/// standard 30% CIT rate plus 4% Development Levy applies.
class TaxPolicy {
  TaxPolicy._();

  static const double smallCompanyTurnoverThreshold = 100000000.0; // ₦100,000,000
  static const double approachingThresholdRatio = 0.85; // warn at 85% of the limit

  static double get approachingThreshold =>
      smallCompanyTurnoverThreshold * approachingThresholdRatio;
}
