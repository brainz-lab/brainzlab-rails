# frozen_string_literal: true

require 'socket'

module BrainzLab
  module Rails
    class Configuration
      # Product routing - which products receive which events
      attr_accessor :pulse_enabled      # APM tracing
      attr_accessor :recall_enabled     # Structured logging
      attr_accessor :reflex_enabled     # Error tracking
      attr_accessor :flux_enabled       # Metrics
      attr_accessor :nerve_enabled      # Job monitoring

      # Collector settings
      attr_accessor :action_controller_enabled
      attr_accessor :action_view_enabled
      attr_accessor :active_record_enabled
      attr_accessor :active_job_enabled
      attr_accessor :action_cable_enabled
      attr_accessor :action_mailer_enabled
      attr_accessor :active_storage_enabled
      attr_accessor :cache_enabled

      # Analyzer settings
      attr_accessor :n_plus_one_detection
      attr_accessor :slow_query_threshold_ms
      attr_accessor :cache_efficiency_tracking

      # Filtering
      attr_accessor :ignored_actions        # Controller actions to ignore
      attr_accessor :ignored_sql_patterns   # SQL patterns to ignore (e.g., SCHEMA queries)
      attr_accessor :ignored_job_classes    # Job classes to ignore

      # Sampling
      attr_accessor :sample_rate            # 0.0 to 1.0, percentage of events to capture

      # Performance
      attr_accessor :async_processing       # Process events asynchronously
      attr_accessor :batch_size             # Batch events before sending
      attr_accessor :flush_interval_ms      # Flush interval for batched events

      class << self
        # Auto-detect secret key from multiple sources
        # Priority: ENV > Rails credentials > nil
        def detect_secret_key
          # 1. Environment variable (highest priority)
          return ENV['BRAINZLAB_SECRET_KEY'] if ENV['BRAINZLAB_SECRET_KEY'].to_s.strip.length.positive?

          # 2. Rails credentials (encrypted)
          if defined?(::Rails) && ::Rails.application.respond_to?(:credentials)
            credentials = ::Rails.application.credentials

            # Try nested brainzlab.secret_key first
            if credentials.respond_to?(:brainzlab) && credentials.brainzlab.respond_to?(:secret_key)
              key = credentials.brainzlab.secret_key
              return key if key.to_s.strip.length.positive?
            end

            # Try top-level brainzlab_secret_key
            if credentials.respond_to?(:brainzlab_secret_key)
              key = credentials.brainzlab_secret_key
              return key if key.to_s.strip.length.positive?
            end
          end

          nil
        end

        # Auto-detect environment from Rails
        def detect_environment
          return ::Rails.env.to_s if defined?(::Rails) && ::Rails.respond_to?(:env)

          ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
        end

        # Auto-detect service name from Rails application
        def detect_service_name
          return ENV['BRAINZLAB_SERVICE'] if ENV['BRAINZLAB_SERVICE'].to_s.strip.length.positive?

          if defined?(::Rails) && ::Rails.application
            begin
              ::Rails.application.class.module_parent_name.underscore.tr('_', '-')
            rescue StandardError
              nil
            end
          end
        end

        # Auto-detect hostname
        def detect_hostname
          return ENV['BRAINZLAB_HOST'] if ENV['BRAINZLAB_HOST'].to_s.strip.length.positive?

          Socket.gethostname
        rescue StandardError
          nil
        end

        # Auto-detect app name for auto-provisioning
        def detect_app_name
          return ENV['BRAINZLAB_APP_NAME'] if ENV['BRAINZLAB_APP_NAME'].to_s.strip.length.positive?

          if defined?(::Rails) && ::Rails.application
            begin
              ::Rails.application.class.module_parent_name.underscore.tr('_', '-')
            rescue StandardError
              nil
            end
          end
        end

        # Auto-detect master keys from credentials
        def detect_master_keys
          keys = {}

          if defined?(::Rails) && ::Rails.application.respond_to?(:credentials)
            credentials = ::Rails.application.credentials

            # Check for nested brainzlab credentials
            if credentials.respond_to?(:brainzlab) && credentials.brainzlab.is_a?(Hash)
              brainzlab = credentials.brainzlab
              keys[:recall_master_key] = brainzlab[:recall_master_key] if brainzlab[:recall_master_key]
              keys[:reflex_master_key] = brainzlab[:reflex_master_key] if brainzlab[:reflex_master_key]
              keys[:pulse_master_key] = brainzlab[:pulse_master_key] if brainzlab[:pulse_master_key]
              keys[:flux_master_key] = brainzlab[:flux_master_key] if brainzlab[:flux_master_key]
              keys[:nerve_master_key] = brainzlab[:nerve_master_key] if brainzlab[:nerve_master_key]
            end
          end

          # ENV overrides credentials
          keys[:recall_master_key] = ENV['RECALL_MASTER_KEY'] if ENV['RECALL_MASTER_KEY']
          keys[:reflex_master_key] = ENV['REFLEX_MASTER_KEY'] if ENV['REFLEX_MASTER_KEY']
          keys[:pulse_master_key] = ENV['PULSE_MASTER_KEY'] if ENV['PULSE_MASTER_KEY']
          keys[:flux_master_key] = ENV['FLUX_MASTER_KEY'] if ENV['FLUX_MASTER_KEY']
          keys[:nerve_master_key] = ENV['NERVE_MASTER_KEY'] if ENV['NERVE_MASTER_KEY']

          keys
        end
      end

      def initialize
        # Default: all products enabled (respects main SDK settings)
        @pulse_enabled = true
        @recall_enabled = true
        @reflex_enabled = true
        @flux_enabled = true
        @nerve_enabled = true

        # Default: all collectors enabled
        @action_controller_enabled = true
        @action_view_enabled = true
        @active_record_enabled = true
        @active_job_enabled = true
        @action_cable_enabled = true
        @action_mailer_enabled = true
        @active_storage_enabled = true
        @cache_enabled = true

        # Default: analyzers enabled with sensible thresholds
        @n_plus_one_detection = true
        @slow_query_threshold_ms = 100
        @cache_efficiency_tracking = true

        # Default: ignore common noise
        @ignored_actions = []
        @ignored_sql_patterns = [
          /\ASELECT.*FROM.*schema_migrations/i,
          /\ASELECT.*FROM.*ar_internal_metadata/i
        ]
        @ignored_job_classes = []

        # Default: capture everything
        @sample_rate = 1.0

        # Default: async with batching
        @async_processing = true
        @batch_size = 100
        @flush_interval_ms = 1000
      end

      def pulse_effectively_enabled?
        @pulse_enabled && BrainzLab.configuration&.pulse_effectively_enabled?
      end

      def recall_effectively_enabled?
        @recall_enabled && BrainzLab.configuration&.recall_effectively_enabled?
      end

      def reflex_effectively_enabled?
        @reflex_enabled && BrainzLab.configuration&.reflex_effectively_enabled?
      end

      def flux_effectively_enabled?
        @flux_enabled && BrainzLab.configuration&.flux_enabled
      end

      def nerve_effectively_enabled?
        @nerve_enabled
      end

      def should_sample?
        return true if @sample_rate >= 1.0
        return false if @sample_rate <= 0.0

        rand < @sample_rate
      end

      def ignored_action?(controller, action)
        @ignored_actions.include?("#{controller}##{action}")
      end

      def ignored_sql?(sql)
        @ignored_sql_patterns.any? { |pattern| sql.match?(pattern) }
      end

      def ignored_job?(job_class)
        @ignored_job_classes.include?(job_class.to_s)
      end
    end
  end
end
