# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Active Support Cache events
      # Tracks cache efficiency and performance
      class Cache < Base
        def initialize(configuration)
          super
          @cache_analyzer = Analyzers::CacheEfficiency.new
        end

        def process(event_data)
          case event_data[:name]
          when 'cache_read.active_support'
            handle_read(event_data)
          when 'cache_read_multi.active_support'
            handle_read_multi(event_data)
          when 'cache_generate.active_support'
            handle_generate(event_data)
          when 'cache_fetch_hit.active_support'
            handle_fetch_hit(event_data)
          when 'cache_write.active_support'
            handle_write(event_data)
          when 'cache_write_multi.active_support'
            handle_write_multi(event_data)
          when 'cache_increment.active_support'
            handle_increment(event_data)
          when 'cache_decrement.active_support'
            handle_decrement(event_data)
          when 'cache_delete.active_support'
            handle_delete(event_data)
          when 'cache_delete_multi.active_support'
            handle_delete_multi(event_data)
          when 'cache_delete_matched.active_support'
            handle_delete_matched(event_data)
          when 'cache_cleanup.active_support'
            handle_cleanup(event_data)
          when 'cache_prune.active_support'
            handle_prune(event_data)
          when 'cache_exist?.active_support'
            handle_exist(event_data)
          when 'message_serializer_fallback.active_support'
            handle_serializer_fallback(event_data)
          end

          # Track cache efficiency if enabled
          if @configuration.cache_efficiency_tracking
            @cache_analyzer.track(event_data)
          end
        end

        private

        def handle_read(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]
          hit = payload[:hit]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Cache read span ===
          send_to_pulse(event_data, {
            name: "cache.read",
            category: 'cache.read',
            attributes: {
              key: truncate_key(key),
              store: store,
              hit: hit,
              super_operation: payload[:super_operation]
            }
          })

          # === FLUX: Metrics ===
          tags = { store: store }
          send_to_flux(:increment, 'rails.cache.reads', 1, tags)
          send_to_flux(:increment, hit ? 'rails.cache.hits' : 'rails.cache.misses', 1, tags)
          send_to_flux(:timing, 'rails.cache.read_ms', duration_ms, tags)

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache #{hit ? 'hit' : 'miss'}: #{truncate_key(key)}",
            category: 'cache.read',
            level: :debug,
            data: {
              key: truncate_key(key),
              hit: hit,
              duration_ms: duration_ms
            }
          )
        end

        def handle_read_multi(event_data)
          payload = event_data[:payload]
          keys = payload[:key] || []
          store = payload[:store]
          hits = payload[:hits] || []
          duration_ms = event_data[:duration_ms]

          hit_count = hits.size
          miss_count = keys.size - hit_count
          hit_rate = keys.size > 0 ? (hit_count.to_f / keys.size * 100).round(1) : 0

          # === PULSE: Multi-read span ===
          send_to_pulse(event_data, {
            name: "cache.read_multi",
            category: 'cache.read',
            attributes: {
              key_count: keys.size,
              hit_count: hit_count,
              miss_count: miss_count,
              hit_rate: hit_rate,
              store: store
            }
          })

          # === FLUX: Metrics ===
          tags = { store: store }
          send_to_flux(:increment, 'rails.cache.multi_reads', 1, tags)
          send_to_flux(:increment, 'rails.cache.hits', hit_count, tags)
          send_to_flux(:increment, 'rails.cache.misses', miss_count, tags)
          send_to_flux(:histogram, 'rails.cache.multi_read_keys', keys.size, tags)
          send_to_flux(:timing, 'rails.cache.read_multi_ms', duration_ms, tags)

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache multi-read: #{keys.size} keys (#{hit_rate}% hit rate)",
            category: 'cache.read',
            level: :debug,
            data: {
              key_count: keys.size,
              hit_count: hit_count,
              hit_rate: hit_rate
            }
          )
        end

        def handle_generate(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]
          duration_ms = event_data[:duration_ms]

          # This fires on cache miss + block execution
          # === PULSE: Cache generate span ===
          send_to_pulse(event_data, {
            name: "cache.generate",
            category: 'cache.generate',
            attributes: {
              key: truncate_key(key),
              store: store
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.generates', 1, { store: store })
          send_to_flux(:timing, 'rails.cache.generate_ms', duration_ms, { store: store })

          # Flag slow cache generations
          if duration_ms > 100
            send_to_recall(:warn, "Slow cache generation", {
              key: truncate_key(key),
              duration_ms: duration_ms
            })
          end
        end

        def handle_fetch_hit(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]

          # === FLUX: Fetch hit metrics ===
          send_to_flux(:increment, 'rails.cache.fetch_hits', 1, { store: store })
        end

        def handle_write(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Cache write span ===
          send_to_pulse(event_data, {
            name: "cache.write",
            category: 'cache.write',
            attributes: {
              key: truncate_key(key),
              store: store
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.writes', 1, { store: store })
          send_to_flux(:timing, 'rails.cache.write_ms', duration_ms, { store: store })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache write: #{truncate_key(key)}",
            category: 'cache.write',
            level: :debug,
            data: {
              key: truncate_key(key),
              duration_ms: duration_ms
            }
          )
        end

        def handle_write_multi(event_data)
          payload = event_data[:payload]
          keys = payload[:key]&.keys || []
          store = payload[:store]
          duration_ms = event_data[:duration_ms]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.multi_writes', 1, { store: store })
          send_to_flux(:histogram, 'rails.cache.multi_write_keys', keys.size, { store: store })
          send_to_flux(:timing, 'rails.cache.write_multi_ms', duration_ms, { store: store })
        end

        def handle_increment(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          amount = payload[:amount]
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.increments', 1, { store: store })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache increment: #{truncate_key(key)} by #{amount}",
            category: 'cache.counter',
            level: :debug,
            data: { key: truncate_key(key), amount: amount }
          )
        end

        def handle_decrement(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          amount = payload[:amount]
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.decrements', 1, { store: store })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache decrement: #{truncate_key(key)} by #{amount}",
            category: 'cache.counter',
            level: :debug,
            data: { key: truncate_key(key), amount: amount }
          )
        end

        def handle_delete(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.deletes', 1, { store: store })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cache delete: #{truncate_key(key)}",
            category: 'cache.delete',
            level: :debug,
            data: { key: truncate_key(key) }
          )
        end

        def handle_delete_multi(event_data)
          payload = event_data[:payload]
          keys = payload[:key] || []
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.multi_deletes', 1, { store: store })
          send_to_flux(:histogram, 'rails.cache.multi_delete_keys', keys.size, { store: store })
        end

        def handle_delete_matched(event_data)
          payload = event_data[:payload]
          pattern = payload[:key]
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.pattern_deletes', 1, { store: store })

          # === RECALL: Log pattern delete ===
          send_to_recall(:info, "Cache pattern delete", {
            pattern: pattern.to_s,
            store: store
          })
        end

        def handle_cleanup(event_data)
          payload = event_data[:payload]
          store = payload[:store]
          size = payload[:size]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.cleanups', 1, { store: store })
          send_to_flux(:gauge, 'rails.cache.size_before_cleanup', size, { store: store })

          # === RECALL: Log cleanup ===
          send_to_recall(:info, "Cache cleanup", {
            store: store,
            size_before: size
          })
        end

        def handle_prune(event_data)
          payload = event_data[:payload]
          store = payload[:store]
          target_size = payload[:key]
          from_size = payload[:from]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.prunes', 1, { store: store })
          send_to_flux(:gauge, 'rails.cache.prune_from', from_size, { store: store })
          send_to_flux(:gauge, 'rails.cache.prune_target', target_size, { store: store })

          # === RECALL: Log prune ===
          send_to_recall(:info, "Cache prune", {
            store: store,
            from_bytes: from_size,
            target_bytes: target_size
          })
        end

        def handle_exist(event_data)
          payload = event_data[:payload]
          key = payload[:key]
          store = payload[:store]

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.exist_checks', 1, { store: store })
        end

        def handle_serializer_fallback(event_data)
          payload = event_data[:payload]
          serializer = payload[:serializer]
          fallback = payload[:fallback]
          duration_ms = event_data[:duration_ms]

          # === RECALL: Warn about serializer fallback ===
          send_to_recall(:warn, "Message serializer fallback", {
            serializer: serializer.to_s,
            fallback: fallback.to_s,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Serializer fallback: #{serializer} -> #{fallback}",
            category: 'cache.serializer',
            level: :warning,
            data: {
              serializer: serializer.to_s,
              fallback: fallback.to_s
            }
          )

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cache.serializer_fallbacks', 1, {
            serializer: serializer.to_s,
            fallback: fallback.to_s
          })
        end

        def truncate_key(key, max_length = 100)
          return '' if key.nil?

          key_str = key.to_s
          key_str.length > max_length ? "#{key_str[0, max_length]}..." : key_str
        end
      end
    end
  end
end
