# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Action Cable WebSocket events
      # This is a KEY differentiator - most APM tools have weak WebSocket support
      class ActionCable < Base
        def process(event_data)
          case event_data[:name]
          when 'perform_action.action_cable'
            handle_perform_action(event_data)
          when 'transmit.action_cable'
            handle_transmit(event_data)
          when 'transmit_subscription_confirmation.action_cable'
            handle_subscription_confirmation(event_data)
          when 'transmit_subscription_rejection.action_cable'
            handle_subscription_rejection(event_data)
          when 'broadcast.action_cable'
            handle_broadcast(event_data)
          end
        end

        private

        def handle_perform_action(event_data)
          payload = event_data[:payload]
          channel_class = payload[:channel_class]
          action = payload[:action]
          duration_ms = event_data[:duration_ms]

          # === PULSE: WebSocket action span ===
          send_to_pulse(event_data, {
            name: "cable.#{channel_class}##{action}",
            category: 'websocket.action',
            attributes: {
              channel: channel_class,
              action: action,
              data_size: payload[:data]&.to_json&.bytesize
            }
          })

          # === FLUX: Metrics ===
          tags = { channel: channel_class, action: action }
          send_to_flux(:increment, 'rails.cable.actions', 1, tags)
          send_to_flux(:timing, 'rails.cable.action_ms', duration_ms, tags)

          # === RECALL: Log ===
          send_to_recall(:info, "Cable action: #{channel_class}##{action}", {
            channel: channel_class,
            action: action,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cable action: #{channel_class}##{action}",
            category: 'websocket.action',
            level: :info,
            data: {
              channel: channel_class,
              action: action,
              duration_ms: duration_ms
            }
          )
        end

        def handle_transmit(event_data)
          payload = event_data[:payload]
          channel_class = payload[:channel_class]
          via = payload[:via]
          duration_ms = event_data[:duration_ms]

          # Calculate data size for bandwidth tracking
          data_size = payload[:data]&.to_json&.bytesize || 0

          # === PULSE: Transmit span ===
          send_to_pulse(event_data, {
            name: "cable.transmit.#{channel_class}",
            category: 'websocket.transmit',
            attributes: {
              channel: channel_class,
              via: via,
              data_size_bytes: data_size
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.cable.transmissions', 1, {
            channel: channel_class
          })
          send_to_flux(:histogram, 'rails.cable.transmit_bytes', data_size, {
            channel: channel_class
          })
          send_to_flux(:timing, 'rails.cable.transmit_ms', duration_ms, {
            channel: channel_class
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cable transmit: #{channel_class}",
            category: 'websocket.transmit',
            level: :debug,
            data: {
              channel: channel_class,
              via: via,
              data_size_bytes: data_size
            }
          )
        end

        def handle_subscription_confirmation(event_data)
          payload = event_data[:payload]
          channel_class = payload[:channel_class]

          # === FLUX: Subscription metrics ===
          send_to_flux(:increment, 'rails.cable.subscriptions', 1, {
            channel: channel_class,
            status: 'confirmed'
          })

          # === RECALL: Log ===
          send_to_recall(:info, "Cable subscription confirmed", {
            channel: channel_class
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cable subscribed: #{channel_class}",
            category: 'websocket.subscribe',
            level: :info,
            data: { channel: channel_class }
          )
        end

        def handle_subscription_rejection(event_data)
          payload = event_data[:payload]
          channel_class = payload[:channel_class]

          # === FLUX: Rejection metrics ===
          send_to_flux(:increment, 'rails.cable.subscriptions', 1, {
            channel: channel_class,
            status: 'rejected'
          })

          # === RECALL: Log rejection (potential auth issue) ===
          send_to_recall(:warn, "Cable subscription rejected", {
            channel: channel_class
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cable subscription rejected: #{channel_class}",
            category: 'websocket.subscribe',
            level: :warning,
            data: { channel: channel_class }
          )
        end

        def handle_broadcast(event_data)
          payload = event_data[:payload]
          broadcasting = payload[:broadcasting]
          coder = payload[:coder]
          duration_ms = event_data[:duration_ms]

          # Calculate message size
          message_size = payload[:message]&.to_json&.bytesize || 0

          # === PULSE: Broadcast span ===
          send_to_pulse(event_data, {
            name: "cable.broadcast.#{broadcasting}",
            category: 'websocket.broadcast',
            attributes: {
              broadcasting: broadcasting,
              coder: coder.to_s,
              message_size_bytes: message_size
            }
          })

          # === FLUX: Broadcast metrics ===
          send_to_flux(:increment, 'rails.cable.broadcasts', 1, {
            broadcasting: broadcasting
          })
          send_to_flux(:histogram, 'rails.cable.broadcast_bytes', message_size, {
            broadcasting: broadcasting
          })
          send_to_flux(:timing, 'rails.cable.broadcast_ms', duration_ms, {
            broadcasting: broadcasting
          })

          # === RECALL: Log broadcast ===
          send_to_recall(:info, "Cable broadcast", {
            broadcasting: broadcasting,
            message_size_bytes: message_size,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Cable broadcast: #{broadcasting}",
            category: 'websocket.broadcast',
            level: :info,
            data: {
              broadcasting: broadcasting,
              message_size_bytes: message_size
            }
          )
        end
      end
    end
  end
end
