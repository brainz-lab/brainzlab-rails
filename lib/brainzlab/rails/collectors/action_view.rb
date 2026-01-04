# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Action View rendering events
      # Tracks template, partial, and layout rendering performance
      class ActionView < Base
        def process(event_data)
          case event_data[:name]
          when 'render_template.action_view'
            handle_render_template(event_data)
          when 'render_partial.action_view'
            handle_render_partial(event_data)
          when 'render_collection.action_view'
            handle_render_collection(event_data)
          when 'render_layout.action_view'
            handle_render_layout(event_data)
          end
        end

        private

        def handle_render_template(event_data)
          payload = event_data[:payload]
          identifier = extract_template_name(payload[:identifier])
          duration_ms = event_data[:duration_ms]

          # === PULSE: View rendering span ===
          send_to_pulse(event_data, {
            name: "render_template.#{identifier}",
            category: 'view.template',
            attributes: {
              identifier: identifier,
              layout: payload[:layout]
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:timing, 'rails.view.template_ms', duration_ms, {
            template: identifier
          })
          send_to_flux(:increment, 'rails.view.templates_rendered', 1)

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Rendered #{identifier}",
            category: 'view.render',
            level: :debug,
            data: {
              template: identifier,
              layout: payload[:layout],
              duration_ms: duration_ms
            }
          )
        end

        def handle_render_partial(event_data)
          payload = event_data[:payload]
          identifier = extract_template_name(payload[:identifier])
          duration_ms = event_data[:duration_ms]

          # === PULSE: Partial rendering span ===
          send_to_pulse(event_data, {
            name: "render_partial.#{identifier}",
            category: 'view.partial',
            attributes: {
              identifier: identifier
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:timing, 'rails.view.partial_ms', duration_ms, {
            partial: identifier
          })
          send_to_flux(:increment, 'rails.view.partials_rendered', 1)

          # Flag slow partials (> 50ms is concerning for a partial)
          if duration_ms > 50
            send_to_recall(:warn, "Slow partial rendering", {
              partial: identifier,
              duration_ms: duration_ms
            })
          end
        end

        def handle_render_collection(event_data)
          payload = event_data[:payload]
          identifier = extract_template_name(payload[:identifier])
          count = payload[:count] || 0
          cache_hits = payload[:cache_hits] || 0
          duration_ms = event_data[:duration_ms]

          # === PULSE: Collection rendering span ===
          send_to_pulse(event_data, {
            name: "render_collection.#{identifier}",
            category: 'view.collection',
            attributes: {
              identifier: identifier,
              count: count,
              cache_hits: cache_hits,
              cache_hit_rate: count > 0 ? (cache_hits.to_f / count * 100).round(1) : 0
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:timing, 'rails.view.collection_ms', duration_ms, {
            partial: identifier
          })
          send_to_flux(:gauge, 'rails.view.collection_size', count)

          if cache_hits > 0
            send_to_flux(:increment, 'rails.view.collection_cache_hits', cache_hits)
          end

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Rendered collection #{identifier} (#{count} items, #{cache_hits} cached)",
            category: 'view.collection',
            level: :debug,
            data: {
              partial: identifier,
              count: count,
              cache_hits: cache_hits,
              duration_ms: duration_ms
            }
          )

          # Flag potentially slow collection renders
          if count > 0 && duration_ms / count > 10
            send_to_recall(:warn, "Slow collection item rendering", {
              partial: identifier,
              count: count,
              avg_ms_per_item: (duration_ms / count).round(2),
              total_duration_ms: duration_ms
            })
          end
        end

        def handle_render_layout(event_data)
          payload = event_data[:payload]
          identifier = extract_template_name(payload[:identifier])
          duration_ms = event_data[:duration_ms]

          # === PULSE: Layout rendering span ===
          send_to_pulse(event_data, {
            name: "render_layout.#{identifier}",
            category: 'view.layout',
            attributes: {
              identifier: identifier
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:timing, 'rails.view.layout_ms', duration_ms, {
            layout: identifier
          })
        end

        # Extract clean template name from full path
        def extract_template_name(identifier)
          return 'unknown' if identifier.nil?

          # Extract the relative path from app/views
          if identifier.include?('/app/views/')
            identifier.split('/app/views/').last
          elsif identifier.include?('/views/')
            identifier.split('/views/').last
          else
            File.basename(identifier)
          end
        end
      end
    end
  end
end
