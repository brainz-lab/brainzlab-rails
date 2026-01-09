# frozen_string_literal: true

module BrainzLab
  module Rails
    # Railtie for automatic Rails integration
    # Automatically starts instrumentation when Rails boots
    class Railtie < ::Rails::Railtie
      config.brainzlab_rails = ActiveSupport::OrderedOptions.new

      # Include view helpers in Action View
      initializer 'brainzlab_rails.view_helpers' do
        ActiveSupport.on_load(:action_view) do
          include BrainzLab::Rails::ViewHelpers
        end
      end

      # Initialize after Rails and BrainzLab SDK are configured
      initializer 'brainzlab_rails.setup', after: :load_config_initializers do |app|
        # Configure from Rails config if provided
        BrainzLab::Rails.configure do |config|
          rails_config = app.config.brainzlab_rails

          # Copy any Rails-level configuration
          config.pulse_enabled = rails_config.pulse_enabled if rails_config.key?(:pulse_enabled)
          config.recall_enabled = rails_config.recall_enabled if rails_config.key?(:recall_enabled)
          config.reflex_enabled = rails_config.reflex_enabled if rails_config.key?(:reflex_enabled)
          config.flux_enabled = rails_config.flux_enabled if rails_config.key?(:flux_enabled)
          config.nerve_enabled = rails_config.nerve_enabled if rails_config.key?(:nerve_enabled)

          # Collector settings
          config.action_controller_enabled = rails_config.action_controller_enabled if rails_config.key?(:action_controller_enabled)
          config.action_view_enabled = rails_config.action_view_enabled if rails_config.key?(:action_view_enabled)
          config.active_record_enabled = rails_config.active_record_enabled if rails_config.key?(:active_record_enabled)
          config.active_job_enabled = rails_config.active_job_enabled if rails_config.key?(:active_job_enabled)
          config.action_cable_enabled = rails_config.action_cable_enabled if rails_config.key?(:action_cable_enabled)
          config.action_mailer_enabled = rails_config.action_mailer_enabled if rails_config.key?(:action_mailer_enabled)
          config.active_storage_enabled = rails_config.active_storage_enabled if rails_config.key?(:active_storage_enabled)
          config.cache_enabled = rails_config.cache_enabled if rails_config.key?(:cache_enabled)

          # Analyzer settings
          config.n_plus_one_detection = rails_config.n_plus_one_detection if rails_config.key?(:n_plus_one_detection)
          config.slow_query_threshold_ms = rails_config.slow_query_threshold_ms if rails_config.key?(:slow_query_threshold_ms)
          config.cache_efficiency_tracking = rails_config.cache_efficiency_tracking if rails_config.key?(:cache_efficiency_tracking)

          # Filtering
          config.ignored_actions = rails_config.ignored_actions if rails_config.key?(:ignored_actions)
          config.ignored_sql_patterns = rails_config.ignored_sql_patterns if rails_config.key?(:ignored_sql_patterns)
          config.ignored_job_classes = rails_config.ignored_job_classes if rails_config.key?(:ignored_job_classes)

          # Sampling
          config.sample_rate = rails_config.sample_rate if rails_config.key?(:sample_rate)
        end
      end

      # Start instrumentation when Rails is ready
      config.after_initialize do
        # Only start if BrainzLab SDK is configured
        # Check for either secret_key (legacy) or any product enabled with auto-provisioning
        if sdk_configured?
          BrainzLab::Rails.start!
          ::Rails.logger.info '[BrainzLab::Rails] Instrumentation started (SDK Rails events delegated)'
        else
          ::Rails.logger.warn '[BrainzLab::Rails] BrainzLab SDK not configured, skipping instrumentation'
        end
      end

      def self.sdk_configured?
        config = BrainzLab.configuration
        return false unless config

        # Check for secret_key (set directly or by auto-provisioning)
        return true if config.secret_key.to_s.strip.length.positive?

        # Check if any product can auto-provision
        # Products with auto_provision + master_key will provision on first use
        products_with_auto = %i[recall reflex pulse flux]
        has_auto_provision = products_with_auto.any? do |product|
          enabled = config.send("#{product}_enabled")
          can_provision = config.send("#{product}_auto_provision") &&
                          config.send("#{product}_master_key").to_s.strip.length.positive? &&
                          config.app_name.to_s.strip.length.positive?
          enabled && can_provision
        end
        return true if has_auto_provision

        # Check for direct API keys
        direct_keys = {
          reflex: :reflex_api_key,
          pulse: :pulse_api_key,
          flux: :flux_api_key
        }
        direct_keys.any? do |product, key_method|
          config.send("#{product}_enabled") &&
            config.send(key_method).to_s.strip.length.positive?
        end
      end

      # Expose configuration in Rails console
      console do
        puts '[BrainzLab::Rails] Rails instrumentation active'
        puts "  Hit rate: #{BrainzLab::Rails.subscriber&.event_router&.collectors&.dig(:cache)&.instance_variable_get(:@cache_analyzer)&.hit_rate}%" rescue nil
      end
    end
  end
end
