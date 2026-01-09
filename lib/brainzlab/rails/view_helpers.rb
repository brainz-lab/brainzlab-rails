# frozen_string_literal: true

module BrainzLab
  module Rails
    # View helpers for integrating BrainzLab JS SDK
    module ViewHelpers
      # Outputs a script tag with BrainzLab JS SDK configuration
      # Use in your layout's <head> section:
      #
      #   <%= brainzlab_js_config %>
      #
      # This will output the configuration from brainzlab-rails
      # so the JS SDK can pick up endpoints and API keys automatically
      #
      def brainzlab_js_config(options = {})
        config = BrainzLab.configuration
        return "".html_safe unless config

        js_config = {
          debug: options[:debug] || ::Rails.env.development?,
          environment: config.environment || ::Rails.env,
          service: config.service || config.app_name,
          release: config.commit, # SDK uses commit instead of release
          sampleRate: options[:sample_rate] || 1.0,
          enableErrors: options.fetch(:enable_errors, true),
          enableNetwork: options.fetch(:enable_network, true),
          enablePerformance: options.fetch(:enable_performance, true),
          enableConsole: options.fetch(:enable_console, true),
          endpoints: {}
        }

        # Add trace context for distributed tracing (links browser events to server requests)
        trace_context = current_trace_context
        if trace_context
          js_config[:traceId] = trace_context[:trace_id]
          js_config[:parentSpanId] = trace_context[:span_id]
          js_config[:sampled] = trace_context[:sampled]
        end

        # Add product endpoints and keys if enabled
        app_name = config.app_name || config.service
        js_config[:apiKeys] = {}

        if config.reflex_enabled
          js_config[:endpoints][:errors] = reflex_browser_url(config)
          js_config[:apiKeys][:errors] = load_auto_provisioned_ingest_key(app_name, 'reflex') if app_name
        end

        if config.pulse_enabled
          js_config[:endpoints][:performance] = pulse_browser_url(config)
          js_config[:endpoints][:network] = pulse_browser_url(config)
          pulse_key = load_auto_provisioned_ingest_key(app_name, 'pulse') if app_name
          js_config[:apiKeys][:performance] = pulse_key
          js_config[:apiKeys][:network] = pulse_key
        end

        if config.recall_enabled
          js_config[:endpoints][:console] = recall_browser_url(config)
          js_config[:apiKeys][:console] = load_auto_provisioned_ingest_key(app_name, 'recall') if app_name
        end

        if config.respond_to?(:signal_enabled) && config.signal_enabled
          js_config[:endpoints][:custom] = signal_browser_url(config)
          # Signal needs explicit provisioning trigger since it's lazy-loaded
          signal_key = load_auto_provisioned_ingest_key(app_name, 'signal') if app_name
          signal_key ||= ensure_signal_provisioned(config)
          js_config[:apiKeys][:custom] = signal_key
        end

        # Add fallback API key for backwards compatibility
        js_config[:apiKey] = find_browser_api_key(config)

        content_tag(:script, "window.BrainzLabConfig = #{js_config.to_json};".html_safe, id: "brainzlab-config")
      end

      # Returns the data attributes for the Stimulus controller
      # Use on your <body> tag:
      #
      #   <body <%= brainzlab_controller_attrs %>>
      #
      def brainzlab_controller_attrs(options = {})
        config = BrainzLab.configuration
        return "" unless config

        attrs = {
          "data-controller" => "brainzlab",
          "data-brainzlab-debug-value" => (options[:debug] || ::Rails.env.development?).to_s,
          "data-brainzlab-environment-value" => config.environment || ::Rails.env,
          "data-brainzlab-service-value" => config.service || config.app_name
        }

        # Add release (commit) if configured
        if config.commit
          attrs["data-brainzlab-release-value"] = config.commit
        end

        # Add endpoints
        if config.reflex_enabled
          attrs["data-brainzlab-reflex-endpoint-value"] = reflex_browser_url(config)
        end

        if config.pulse_enabled
          attrs["data-brainzlab-pulse-endpoint-value"] = pulse_browser_url(config)
        end

        if config.recall_enabled
          attrs["data-brainzlab-recall-endpoint-value"] = recall_browser_url(config)
        end

        # Add API key
        api_key = find_browser_api_key(config)
        attrs["data-brainzlab-api-key-value"] = api_key if api_key

        attrs.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(" ").html_safe
      end

      private

      def find_browser_api_key(config)
        # Try to load auto-provisioned ingest keys from file (preferred for browser - write-only, secure)
        app_name = config.app_name || config.service
        if app_name
          %w[pulse reflex recall].each do |product|
            provisioned_key = load_auto_provisioned_ingest_key(app_name, product)
            return provisioned_key if provisioned_key
          end
        end

        # Fallback to config API keys if no ingest key available
        # Note: This is less secure - consider using auto-provisioning
        key = config.reflex_api_key ||
              config.pulse_api_key ||
              config.recall_api_key ||
              config.secret_key

        return key if key

        # Last resort: try api_key from auto-provisioned files (legacy support)
        if app_name
          %w[pulse reflex recall].each do |product|
            provisioned_key = load_auto_provisioned_api_key(app_name, product)
            return provisioned_key if provisioned_key
          end
        end

        nil
      end

      def load_auto_provisioned_ingest_key(app_name, product)
        file_path = File.expand_path("~/.brainzlab/#{app_name}.#{product}.json")
        return nil unless File.exist?(file_path)

        data = JSON.parse(File.read(file_path))
        # Prefer ingest_key for browser (write-only, secure)
        data['ingest_key']
      rescue StandardError
        nil
      end

      def load_auto_provisioned_api_key(app_name, product)
        file_path = File.expand_path("~/.brainzlab/#{app_name}.#{product}.json")
        return nil unless File.exist?(file_path)

        data = JSON.parse(File.read(file_path))
        data['api_key']
      rescue StandardError
        nil
      end

      def reflex_browser_url(config)
        "#{config.reflex_url}/api/v1/browser"
      end

      def pulse_browser_url(config)
        "#{config.pulse_url}/api/v1/browser"
      end

      def recall_browser_url(config)
        "#{config.recall_url}/api/v1/browser"
      end

      def signal_browser_url(config)
        "#{config.signal_url}/api/v1/browser"
      end

      def ensure_signal_provisioned(config)
        # Trigger Signal provisioning if not already done
        return nil unless defined?(BrainzLab::Signal)
        return nil unless config.respond_to?(:signal_auto_provision) && config.signal_auto_provision

        BrainzLab::Signal.ensure_provisioned!
        # After provisioning, try to load the key again
        app_name = config.app_name || config.service
        load_auto_provisioned_ingest_key(app_name, 'signal')
      rescue StandardError
        nil
      end

      def current_trace_context
        # Get trace context from Pulse propagation (set by middleware)
        propagation_ctx = BrainzLab::Pulse::Propagation.current
        return propagation_ctx.to_h if propagation_ctx&.valid?

        # Fallback: create new trace context for this page load
        # This ensures browser events can still be grouped even without prior context
        request_id = try(:request)&.request_id
        if request_id
          # Use request_id to derive a consistent trace_id for this request
          trace_id = Digest::MD5.hexdigest(request_id)
          span_id = SecureRandom.hex(8)
          {
            trace_id: trace_id,
            span_id: span_id,
            sampled: true
          }
        else
          nil
        end
      rescue StandardError
        nil
      end
    end
  end
end
