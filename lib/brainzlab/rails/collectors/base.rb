# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Base class for all event collectors
      # Provides common functionality for routing events to products
      class Base
        attr_reader :configuration

        def initialize(configuration)
          @configuration = configuration
        end

        def process(event_data)
          raise NotImplementedError, "#{self.class} must implement #process"
        end

        protected

        # Send to Pulse (APM) - performance tracing
        def send_to_pulse(event_data, span_data)
          return unless @configuration.pulse_effectively_enabled?

          BrainzLab::Pulse.record_span(
            name: span_data[:name],
            duration_ms: event_data[:duration_ms],
            category: span_data[:category],
            attributes: span_data[:attributes] || {},
            timestamp: event_data[:timestamp]
          )
        end

        # Send to Recall (Logs) - structured logging
        def send_to_recall(level, message, data = {})
          return unless @configuration.recall_effectively_enabled?

          case level
          when :debug
            BrainzLab::Recall.debug(message, **data)
          when :info
            BrainzLab::Recall.info(message, **data)
          when :warn
            BrainzLab::Recall.warn(message, **data)
          when :error
            BrainzLab::Recall.error(message, **data)
          end
        end

        # Send to Reflex (Errors) - error tracking with context
        def send_to_reflex(exception, context = {})
          return unless @configuration.reflex_effectively_enabled?

          BrainzLab::Reflex.capture(exception, context: context)
        end

        # Add breadcrumb to Reflex
        def add_breadcrumb(message, category:, level: :info, data: {})
          return unless @configuration.reflex_effectively_enabled?

          BrainzLab::Reflex.add_breadcrumb(
            message,
            category: category,
            level: level,
            data: data
          )
        end

        # Send to Flux (Metrics) - counters, gauges, histograms
        def send_to_flux(metric_type, metric_name, value, tags = {})
          return unless @configuration.flux_effectively_enabled?

          case metric_type
          when :increment
            BrainzLab::Flux.increment(metric_name, value, tags: tags)
          when :gauge
            BrainzLab::Flux.gauge(metric_name, value, tags: tags)
          when :histogram
            BrainzLab::Flux.histogram(metric_name, value, tags: tags)
          when :timing
            BrainzLab::Flux.timing(metric_name, value, tags: tags)
          end
        end

        # Send to Nerve (Jobs) - job-specific tracking
        def send_to_nerve(job_event_type, job_data)
          return unless @configuration.nerve_effectively_enabled?

          # Nerve integration for job monitoring
          # This will be expanded as Nerve product develops
          BrainzLab.debug_log("[Nerve] #{job_event_type}: #{job_data.inspect}")
        end

        # Extract common request context
        def extract_request_context(payload)
          request = payload[:request]
          return {} unless request

          {
            request_id: request.request_id,
            method: request.method,
            path: request.path,
            format: request.format&.to_s,
            remote_ip: request.remote_ip,
            user_agent: request.user_agent
          }.compact
        end

        # Sanitize sensitive data from params
        def sanitize_params(params)
          return {} unless params.is_a?(Hash)

          sensitive_keys = %w[password password_confirmation token api_key secret]
          params.transform_values.with_index do |(key, value), _|
            if sensitive_keys.any? { |sk| key.to_s.downcase.include?(sk) }
              '[FILTERED]'
            elsif value.is_a?(Hash)
              sanitize_params(value)
            else
              value
            end
          end
        rescue StandardError
          {}
        end
      end
    end
  end
end
