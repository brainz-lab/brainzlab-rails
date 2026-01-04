# frozen_string_literal: true

module BrainzLab
  module Rails
    # Central subscriber that hooks into ALL Rails ActiveSupport::Notifications
    # Uses monotonic_subscribe for accurate timing measurements
    class Subscriber
      RAILS_EVENT_PATTERNS = [
        # Action Controller
        'start_processing.action_controller',
        'process_action.action_controller',
        'redirect_to.action_controller',
        'halted_callback.action_controller',
        'send_file.action_controller',
        'send_data.action_controller',
        'send_stream.action_controller',
        'unpermitted_parameters.action_controller',
        'rate_limit.action_controller',

        # Action Controller Caching
        'write_fragment.action_controller',
        'read_fragment.action_controller',
        'expire_fragment.action_controller',
        'exist_fragment?.action_controller',

        # Action View
        'render_template.action_view',
        'render_partial.action_view',
        'render_collection.action_view',
        'render_layout.action_view',

        # Action Dispatch
        'process_middleware.action_dispatch',
        'redirect.action_dispatch',
        'request.action_dispatch',

        # Active Record
        'sql.active_record',
        'instantiation.active_record',
        'start_transaction.active_record',
        'transaction.active_record',
        'strict_loading_violation.active_record',

        # Active Job
        'enqueue.active_job',
        'enqueue_at.active_job',
        'enqueue_all.active_job',
        'enqueue_retry.active_job',
        'perform_start.active_job',
        'perform.active_job',
        'retry_stopped.active_job',
        'discard.active_job',

        # Action Cable
        'perform_action.action_cable',
        'transmit.action_cable',
        'transmit_subscription_confirmation.action_cable',
        'transmit_subscription_rejection.action_cable',
        'broadcast.action_cable',

        # Action Mailer
        'deliver.action_mailer',
        'process.action_mailer',

        # Action Mailbox
        'process.action_mailbox',

        # Active Storage
        'service_upload.active_storage',
        'service_streaming_download.active_storage',
        'service_download.active_storage',
        'service_download_chunk.active_storage',
        'service_delete.active_storage',
        'service_delete_prefixed.active_storage',
        'service_exist.active_storage',
        'service_url.active_storage',
        'service_update_metadata.active_storage',
        'preview.active_storage',
        'transform.active_storage',
        'analyze.active_storage',

        # Active Support Cache
        'cache_read.active_support',
        'cache_read_multi.active_support',
        'cache_generate.active_support',
        'cache_fetch_hit.active_support',
        'cache_write.active_support',
        'cache_write_multi.active_support',
        'cache_increment.active_support',
        'cache_decrement.active_support',
        'cache_delete.active_support',
        'cache_delete_multi.active_support',
        'cache_delete_matched.active_support',
        'cache_cleanup.active_support',
        'cache_prune.active_support',
        'cache_exist?.active_support',
        'message_serializer_fallback.active_support',

        # Rails
        'deprecation.rails',

        # Railties
        'load_config_initializer.railties'
      ].freeze

      attr_reader :configuration, :event_router, :subscriptions

      def initialize(configuration)
        @configuration = configuration
        @event_router = EventRouter.new(configuration)
        @subscriptions = []
      end

      def subscribe_all!
        RAILS_EVENT_PATTERNS.each do |event_name|
          subscribe_to(event_name)
        end

        BrainzLab.debug_log("[BrainzLab::Rails] Subscribed to #{@subscriptions.size} events")
      end

      def unsubscribe_all!
        @subscriptions.each do |subscription|
          ActiveSupport::Notifications.unsubscribe(subscription)
        end
        @subscriptions.clear
      end

      private

      def subscribe_to(event_name)
        # Use monotonic_subscribe for accurate timing
        subscription = ActiveSupport::Notifications.monotonic_subscribe(event_name) do |name, started, finished, unique_id, payload|
          handle_event(name, started, finished, unique_id, payload)
        end

        @subscriptions << subscription
      end

      def handle_event(name, started, finished, unique_id, payload)
        return unless @configuration.should_sample?

        # Calculate precise duration using monotonic time
        duration_ms = ((finished - started) * 1000).round(3)

        # Build event data structure
        event_data = {
          name: name,
          started_at: started,
          finished_at: finished,
          duration_ms: duration_ms,
          unique_id: unique_id,
          payload: payload,
          timestamp: Time.now.utc.iso8601(3)
        }

        # Route to appropriate products
        @event_router.route(event_data)
      rescue StandardError => e
        BrainzLab.debug_log("[BrainzLab::Rails] Error handling event #{name}: #{e.message}")
      end
    end
  end
end
