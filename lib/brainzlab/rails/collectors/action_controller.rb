# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Action Controller events and routes to products
      # Primary source for HTTP request observability
      class ActionController < Base
        def process(event_data)
          case event_data[:name]
          when 'start_processing.action_controller'
            handle_start_processing(event_data)
          when 'process_action.action_controller'
            handle_process_action(event_data)
          when 'redirect_to.action_controller'
            handle_redirect(event_data)
          when 'halted_callback.action_controller'
            handle_halted_callback(event_data)
          when 'send_file.action_controller', 'send_data.action_controller', 'send_stream.action_controller'
            handle_send_file(event_data)
          when 'unpermitted_parameters.action_controller'
            handle_unpermitted_parameters(event_data)
          when 'rate_limit.action_controller'
            handle_rate_limit(event_data)
          when /fragment.*\.action_controller$/
            handle_fragment_cache(event_data)
          when 'deprecation.rails'
            handle_deprecation(event_data)
          when 'process_middleware.action_dispatch'
            handle_middleware(event_data)
          when 'redirect.action_dispatch'
            handle_dispatch_redirect(event_data)
          when 'request.action_dispatch'
            handle_dispatch_request(event_data)
          end
        end

        private

        def handle_start_processing(event_data)
          payload = event_data[:payload]
          controller = payload[:controller]
          action = payload[:action]

          return if @configuration.ignored_action?(controller, action)

          # Add breadcrumb for request start
          add_breadcrumb(
            "#{controller}##{action} started",
            category: 'http.request',
            level: :info,
            data: {
              method: payload[:method],
              path: payload[:path],
              format: payload[:format]
            }
          )
        end

        def handle_process_action(event_data)
          payload = event_data[:payload]
          controller = payload[:controller]
          action = payload[:action]
          duration_ms = event_data[:duration_ms]

          return if @configuration.ignored_action?(controller, action)

          # Check for exception
          if payload[:exception_object]
            handle_request_error(event_data, payload[:exception_object])
          end

          # === PULSE: APM Span ===
          send_to_pulse(event_data, {
            name: "#{controller}##{action}",
            category: 'http.request',
            attributes: {
              controller: controller,
              action: action,
              method: payload[:method],
              path: payload[:path],
              status: payload[:status],
              format: payload[:format],
              view_runtime_ms: payload[:view_runtime]&.round(2),
              db_runtime_ms: payload[:db_runtime]&.round(2)
            }
          })

          # === RECALL: Structured Log ===
          log_level = payload[:status].to_i >= 400 ? :warn : :info
          send_to_recall(log_level, "#{payload[:method]} #{payload[:path]}", {
            controller: controller,
            action: action,
            status: payload[:status],
            duration_ms: duration_ms,
            view_runtime_ms: payload[:view_runtime]&.round(2),
            db_runtime_ms: payload[:db_runtime]&.round(2),
            format: payload[:format],
            params: sanitize_params(payload[:params])
          })

          # === FLUX: Metrics ===
          tags = { controller: controller, action: action, status: payload[:status] }
          send_to_flux(:increment, 'rails.requests.total', 1, tags)
          send_to_flux(:timing, 'rails.requests.duration_ms', duration_ms, tags)

          if payload[:view_runtime]
            send_to_flux(:timing, 'rails.view.runtime_ms', payload[:view_runtime], tags)
          end

          if payload[:db_runtime]
            send_to_flux(:timing, 'rails.db.runtime_ms', payload[:db_runtime], tags)
          end

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "#{controller}##{action} completed (#{payload[:status]})",
            category: 'http.request',
            level: payload[:status].to_i >= 400 ? :warning : :info,
            data: {
              status: payload[:status],
              duration_ms: duration_ms
            }
          )
        end

        def handle_request_error(event_data, exception)
          payload = event_data[:payload]

          send_to_reflex(exception, {
            controller: payload[:controller],
            action: payload[:action],
            request_context: extract_request_context(payload),
            params: sanitize_params(payload[:params])
          })

          send_to_flux(:increment, 'rails.requests.errors', 1, {
            controller: payload[:controller],
            action: payload[:action],
            exception_class: exception.class.name
          })
        end

        def handle_redirect(event_data)
          payload = event_data[:payload]

          add_breadcrumb(
            "Redirect to #{payload[:location]}",
            category: 'http.redirect',
            level: :info,
            data: {
              status: payload[:status],
              location: payload[:location]
            }
          )

          send_to_flux(:increment, 'rails.redirects.total', 1, {
            status: payload[:status]
          })
        end

        def handle_halted_callback(event_data)
          payload = event_data[:payload]
          filter = payload[:filter]

          # This is often auth failures - important for security monitoring
          add_breadcrumb(
            "Callback halted by #{filter}",
            category: 'http.callback',
            level: :warning,
            data: { filter: filter.to_s }
          )

          send_to_recall(:warn, "Request halted by callback", {
            filter: filter.to_s
          })

          send_to_flux(:increment, 'rails.callbacks.halted', 1, {
            filter: filter.to_s
          })
        end

        def handle_send_file(event_data)
          payload = event_data[:payload]

          send_to_pulse(event_data, {
            name: "send_file",
            category: 'http.file',
            attributes: payload.slice(:path, :filename, :type, :disposition).compact
          })

          send_to_flux(:increment, 'rails.files.sent', 1)
        end

        def handle_unpermitted_parameters(event_data)
          payload = event_data[:payload]
          keys = payload[:keys]
          context = payload[:context] || {}

          # Security-relevant: log unpermitted params
          send_to_recall(:warn, "Unpermitted parameters detected", {
            keys: keys,
            controller: context[:controller],
            action: context[:action]
          })

          add_breadcrumb(
            "Unpermitted params: #{keys.join(', ')}",
            category: 'security.params',
            level: :warning,
            data: { keys: keys }
          )

          send_to_flux(:increment, 'rails.params.unpermitted', keys.size, {
            controller: context[:controller],
            action: context[:action]
          })
        end

        def handle_rate_limit(event_data)
          payload = event_data[:payload]

          send_to_recall(:warn, "Rate limit exceeded", {
            count: payload[:count],
            limit: payload[:to],
            within: payload[:within],
            name: payload[:name]
          })

          send_to_flux(:increment, 'rails.rate_limit.exceeded', 1, {
            name: payload[:name]
          })
        end

        def handle_fragment_cache(event_data)
          payload = event_data[:payload]
          operation = event_data[:name].split('.').first # read_fragment, write_fragment, etc.

          send_to_flux(:increment, "rails.fragment_cache.#{operation}", 1)

          add_breadcrumb(
            "Fragment cache #{operation}: #{payload[:key]}",
            category: 'cache.fragment',
            level: :debug,
            data: { key: payload[:key] }
          )
        end

        def handle_deprecation(event_data)
          payload = event_data[:payload]

          send_to_recall(:warn, "Deprecation warning: #{payload[:message]}", {
            gem_name: payload[:gem_name],
            deprecation_horizon: payload[:deprecation_horizon],
            callstack: payload[:callstack]&.first(5)&.map(&:to_s)
          })

          send_to_flux(:increment, 'rails.deprecations.total', 1, {
            gem_name: payload[:gem_name]
          })
        end

        def handle_middleware(event_data)
          payload = event_data[:payload]

          send_to_pulse(event_data, {
            name: "middleware.#{payload[:middleware]}",
            category: 'http.middleware',
            attributes: { middleware: payload[:middleware] }
          })
        end

        def handle_dispatch_redirect(event_data)
          payload = event_data[:payload]

          add_breadcrumb(
            "Dispatch redirect to #{payload[:location]}",
            category: 'http.dispatch',
            level: :info,
            data: {
              status: payload[:status],
              location: payload[:location],
              source_location: payload[:source_location]
            }
          )
        end

        def handle_dispatch_request(event_data)
          # Initial request dispatch - useful for timing the full request lifecycle
          send_to_pulse(event_data, {
            name: 'request.dispatch',
            category: 'http.dispatch',
            attributes: {}
          })
        end
      end
    end
  end
end
