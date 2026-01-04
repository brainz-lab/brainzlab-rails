# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Action Mailer events for email observability
      class ActionMailer < Base
        def process(event_data)
          case event_data[:name]
          when 'deliver.action_mailer'
            handle_deliver(event_data)
          when 'process.action_mailer'
            handle_process(event_data)
          when 'process.action_mailbox'
            handle_mailbox_process(event_data)
          end
        end

        private

        def handle_deliver(event_data)
          payload = event_data[:payload]
          mailer = payload[:mailer]
          message_id = payload[:message_id]
          subject = payload[:subject]
          duration_ms = event_data[:duration_ms]

          to_count = Array(payload[:to]).size
          perform_deliveries = payload[:perform_deliveries]

          # === PULSE: Email delivery span ===
          send_to_pulse(event_data, {
            name: "mailer.#{mailer}.deliver",
            category: 'email.deliver',
            attributes: {
              mailer: mailer,
              message_id: message_id,
              subject: truncate_subject(subject),
              to_count: to_count,
              performed: perform_deliveries
            }
          })

          # === FLUX: Metrics ===
          tags = { mailer: mailer, performed: perform_deliveries }
          send_to_flux(:increment, 'rails.mailer.delivered', 1, tags)
          send_to_flux(:timing, 'rails.mailer.delivery_ms', duration_ms, tags)
          send_to_flux(:histogram, 'rails.mailer.recipients', to_count, tags)

          # === RECALL: Log delivery ===
          send_to_recall(:info, "Email delivered", {
            mailer: mailer,
            message_id: message_id,
            subject: truncate_subject(subject),
            to_count: to_count,
            from: payload[:from],
            duration_ms: duration_ms,
            performed: perform_deliveries
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Email: #{mailer} - #{truncate_subject(subject)}",
            category: 'email.deliver',
            level: :info,
            data: {
              mailer: mailer,
              message_id: message_id,
              to_count: to_count,
              duration_ms: duration_ms
            }
          )
        end

        def handle_process(event_data)
          payload = event_data[:payload]
          mailer = payload[:mailer]
          action = payload[:action]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Mailer processing span ===
          send_to_pulse(event_data, {
            name: "mailer.#{mailer}##{action}",
            category: 'email.process',
            attributes: {
              mailer: mailer,
              action: action,
              args: sanitize_mailer_args(payload[:args])
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.mailer.processed', 1, {
            mailer: mailer,
            action: action
          })
          send_to_flux(:timing, 'rails.mailer.process_ms', duration_ms, {
            mailer: mailer,
            action: action
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Mailer: #{mailer}##{action}",
            category: 'email.process',
            level: :debug,
            data: {
              mailer: mailer,
              action: action,
              duration_ms: duration_ms
            }
          )
        end

        def handle_mailbox_process(event_data)
          payload = event_data[:payload]
          mailbox = payload[:mailbox]
          inbound_email = payload[:inbound_email] || {}
          duration_ms = event_data[:duration_ms]

          # === PULSE: Mailbox processing span ===
          send_to_pulse(event_data, {
            name: "mailbox.#{mailbox.class.name}",
            category: 'email.inbound',
            attributes: {
              mailbox: mailbox.class.name,
              message_id: inbound_email[:message_id],
              status: inbound_email[:status]
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.mailbox.processed', 1, {
            mailbox: mailbox.class.name,
            status: inbound_email[:status]
          })
          send_to_flux(:timing, 'rails.mailbox.process_ms', duration_ms, {
            mailbox: mailbox.class.name
          })

          # === RECALL: Log inbound email ===
          send_to_recall(:info, "Inbound email processed", {
            mailbox: mailbox.class.name,
            message_id: inbound_email[:message_id],
            status: inbound_email[:status],
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Mailbox: #{mailbox.class.name}",
            category: 'email.inbound',
            level: :info,
            data: {
              mailbox: mailbox.class.name,
              status: inbound_email[:status],
              duration_ms: duration_ms
            }
          )
        end

        def truncate_subject(subject, max_length = 100)
          return '' if subject.nil?

          subject.length > max_length ? "#{subject[0, max_length]}..." : subject
        end

        def sanitize_mailer_args(args)
          return [] unless args.is_a?(Array)

          args.map do |arg|
            case arg
            when Hash
              sanitize_params(arg)
            when String, Numeric, Symbol, TrueClass, FalseClass, NilClass
              arg
            else
              arg.class.name
            end
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
