# frozen_string_literal: true

module BrainzLab
  module Rails
    module Analyzers
      # Tracks cache efficiency metrics and provides insights
      class CacheEfficiency
        WINDOW_SIZE = 1000 # Rolling window for efficiency calculation

        def initialize
          @hits = 0
          @misses = 0
          @reads = []
          @writes = 0
          @generates = 0
        end

        def track(event_data)
          case event_data[:name]
          when 'cache_read.active_support'
            track_read(event_data)
          when 'cache_read_multi.active_support'
            track_read_multi(event_data)
          when 'cache_write.active_support', 'cache_write_multi.active_support'
            @writes += 1
          when 'cache_generate.active_support'
            @generates += 1
          when 'cache_fetch_hit.active_support'
            @hits += 1
          end

          # Trim old reads to maintain window
          trim_reads if @reads.size > WINDOW_SIZE * 2
        end

        def hit_rate
          total = @hits + @misses
          return 0.0 if total == 0

          (@hits.to_f / total * 100).round(2)
        end

        def efficiency_report
          {
            hit_rate: hit_rate,
            total_hits: @hits,
            total_misses: @misses,
            total_writes: @writes,
            total_generates: @generates,
            recent_reads: recent_reads_stats
          }
        end

        def reset!
          @hits = 0
          @misses = 0
          @reads = []
          @writes = 0
          @generates = 0
        end

        private

        def track_read(event_data)
          payload = event_data[:payload]
          hit = payload[:hit]

          if hit
            @hits += 1
          else
            @misses += 1
          end

          @reads << {
            key: payload[:key],
            hit: hit,
            duration_ms: event_data[:duration_ms],
            timestamp: Time.now
          }
        end

        def track_read_multi(event_data)
          payload = event_data[:payload]
          keys = payload[:key] || []
          hits = payload[:hits] || []

          @hits += hits.size
          @misses += (keys.size - hits.size)

          @reads << {
            key: "multi:#{keys.size}",
            hit: hits.size == keys.size,
            duration_ms: event_data[:duration_ms],
            timestamp: Time.now,
            multi: true,
            hit_count: hits.size,
            total_count: keys.size
          }
        end

        def recent_reads_stats
          return {} if @reads.empty?

          recent = @reads.last(100)
          hits = recent.count { |r| r[:hit] }
          misses = recent.size - hits

          {
            count: recent.size,
            hits: hits,
            misses: misses,
            hit_rate: (hits.to_f / recent.size * 100).round(2),
            avg_duration_ms: (recent.sum { |r| r[:duration_ms] } / recent.size).round(3)
          }
        end

        def trim_reads
          @reads = @reads.last(WINDOW_SIZE)
        end
      end
    end
  end
end
