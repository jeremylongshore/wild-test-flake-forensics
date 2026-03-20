# frozen_string_literal: true

module WildTestFlakeForensics
  module History
    class TrendAnalyzer
      WORSENING_THRESHOLD = 0.05
      IMPROVING_THRESHOLD = -0.05

      def trend(snapshots)
        return :stable if snapshots.size < 2

        sorted = snapshots.sort_by { |s| s[:at] }
        delta = compute_delta(sorted)

        classify_trend(delta)
      end

      def trend_from_rates(rates)
        return :stable if rates.size < 2

        snapshots = rates.each_with_index.map do |rate, i|
          { rate: rate, at: Time.at(i) }
        end
        trend(snapshots)
      end

      private

      def compute_delta(sorted)
        half = sorted.size / 2
        early = sorted.first(half).map { |s| s[:rate] }
        recent = sorted.last(half).map { |s| s[:rate] }

        early_avg = early.sum / early.size.to_f
        recent_avg = recent.sum / recent.size.to_f

        recent_avg - early_avg
      end

      def classify_trend(delta)
        if delta >= WORSENING_THRESHOLD
          :worsening
        elsif delta <= IMPROVING_THRESHOLD
          :improving
        else
          :stable
        end
      end
    end
  end
end
