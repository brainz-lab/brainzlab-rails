# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Active Job events for background job observability
      # Routes to Nerve for specialized job monitoring + other products
      class ActiveJob < Base
        def process(event_data)
          case event_data[:name]
          when 'enqueue.active_job'
            handle_enqueue(event_data)
          when 'enqueue_at.active_job'
            handle_enqueue_at(event_data)
          when 'enqueue_all.active_job'
            handle_enqueue_all(event_data)
          when 'enqueue_retry.active_job'
            handle_enqueue_retry(event_data)
          when 'perform_start.active_job'
            handle_perform_start(event_data)
          when 'perform.active_job'
            handle_perform(event_data)
          when 'retry_stopped.active_job'
            handle_retry_stopped(event_data)
          when 'discard.active_job'
            handle_discard(event_data)
          end
        end

        private

        def handle_enqueue(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name
          queue_name = job.queue_name

          return if @configuration.ignored_job?(job_class)

          # === NERVE: Job enqueued ===
          send_to_nerve(:enqueue, {
            job_id: job.job_id,
            job_class: job_class,
            queue: queue_name,
            arguments: sanitize_job_arguments(job.arguments)
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.jobs.enqueued', 1, {
            job_class: job_class,
            queue: queue_name
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Job enqueued: #{job_class}",
            category: 'job.enqueue',
            level: :info,
            data: {
              job_id: job.job_id,
              queue: queue_name
            }
          )

          # === RECALL: Log ===
          send_to_recall(:info, "Job enqueued", {
            job_id: job.job_id,
            job_class: job_class,
            queue: queue_name
          })
        end

        def handle_enqueue_at(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name

          return if @configuration.ignored_job?(job_class)

          scheduled_at = job.scheduled_at

          # === NERVE: Scheduled job ===
          send_to_nerve(:enqueue_at, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            scheduled_at: scheduled_at
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, 'rails.jobs.scheduled', 1, {
            job_class: job_class,
            queue: job.queue_name
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Job scheduled: #{job_class} at #{scheduled_at}",
            category: 'job.schedule',
            level: :info,
            data: {
              job_id: job.job_id,
              scheduled_at: scheduled_at
            }
          )
        end

        def handle_enqueue_all(event_data)
          payload = event_data[:payload]
          jobs = payload[:jobs] || []

          # === FLUX: Bulk enqueue metrics ===
          send_to_flux(:increment, 'rails.jobs.bulk_enqueued', jobs.size)

          # === RECALL: Log bulk operation ===
          send_to_recall(:info, "Bulk job enqueue", {
            count: jobs.size,
            job_classes: jobs.map { |j| j.class.name }.uniq
          })
        end

        def handle_enqueue_retry(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name
          error = payload[:error]
          wait = payload[:wait]

          return if @configuration.ignored_job?(job_class)

          # === NERVE: Job retry ===
          send_to_nerve(:retry, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            error: error&.message,
            wait_seconds: wait,
            executions: job.executions
          })

          # === FLUX: Retry metrics ===
          send_to_flux(:increment, 'rails.jobs.retries', 1, {
            job_class: job_class,
            queue: job.queue_name
          })

          # === RECALL: Log retry ===
          send_to_recall(:warn, "Job retry scheduled", {
            job_id: job.job_id,
            job_class: job_class,
            error: error&.message,
            wait_seconds: wait,
            executions: job.executions
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Job retry: #{job_class} (attempt #{job.executions})",
            category: 'job.retry',
            level: :warning,
            data: {
              job_id: job.job_id,
              error: error&.message,
              wait_seconds: wait
            }
          )
        end

        def handle_perform_start(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name

          return if @configuration.ignored_job?(job_class)

          # === NERVE: Job started ===
          send_to_nerve(:start, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            executions: job.executions
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Job started: #{job_class}",
            category: 'job.start',
            level: :info,
            data: {
              job_id: job.job_id,
              queue: job.queue_name
            }
          )
        end

        def handle_perform(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name
          duration_ms = event_data[:duration_ms]
          db_runtime = payload[:db_runtime]

          return if @configuration.ignored_job?(job_class)

          # Check for exception
          if payload[:exception_object]
            handle_job_error(event_data, job, payload[:exception_object])
          end

          # === PULSE: Job execution span ===
          send_to_pulse(event_data, {
            name: "job.#{job_class}",
            category: 'job.perform',
            attributes: {
              job_id: job.job_id,
              job_class: job_class,
              queue: job.queue_name,
              executions: job.executions,
              db_runtime_ms: db_runtime&.round(2)
            }
          })

          # === NERVE: Job completed ===
          send_to_nerve(:complete, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            duration_ms: duration_ms,
            db_runtime_ms: db_runtime&.round(2),
            success: payload[:exception_object].nil?
          })

          # === FLUX: Metrics ===
          tags = { job_class: job_class, queue: job.queue_name }
          send_to_flux(:increment, 'rails.jobs.performed', 1, tags)
          send_to_flux(:timing, 'rails.jobs.duration_ms', duration_ms, tags)

          if db_runtime
            send_to_flux(:timing, 'rails.jobs.db_runtime_ms', db_runtime, tags)
          end

          # === RECALL: Log completion ===
          send_to_recall(:info, "Job completed", {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            duration_ms: duration_ms
          })

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "Job completed: #{job_class}",
            category: 'job.complete',
            level: :info,
            data: {
              job_id: job.job_id,
              duration_ms: duration_ms
            }
          )
        end

        def handle_job_error(event_data, job, exception)
          job_class = job.class.name

          # === REFLEX: Capture job error ===
          send_to_reflex(exception, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            executions: job.executions,
            arguments: sanitize_job_arguments(job.arguments)
          })

          # === FLUX: Error metrics ===
          send_to_flux(:increment, 'rails.jobs.errors', 1, {
            job_class: job_class,
            queue: job.queue_name,
            exception_class: exception.class.name
          })
        end

        def handle_retry_stopped(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name
          error = payload[:error]

          return if @configuration.ignored_job?(job_class)

          # === NERVE: Job dead ===
          send_to_nerve(:dead, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            error: error&.message,
            executions: job.executions
          })

          # === REFLEX: Capture final failure ===
          if error
            send_to_reflex(error, {
              job_id: job.job_id,
              job_class: job_class,
              queue: job.queue_name,
              executions: job.executions,
              final_failure: true
            })
          end

          # === FLUX: Dead job metrics ===
          send_to_flux(:increment, 'rails.jobs.dead', 1, {
            job_class: job_class,
            queue: job.queue_name
          })

          # === RECALL: Log final failure ===
          send_to_recall(:error, "Job retries exhausted", {
            job_id: job.job_id,
            job_class: job_class,
            error: error&.message,
            executions: job.executions
          })
        end

        def handle_discard(event_data)
          payload = event_data[:payload]
          job = payload[:job]
          job_class = job.class.name
          error = payload[:error]

          return if @configuration.ignored_job?(job_class)

          # === NERVE: Job discarded ===
          send_to_nerve(:discard, {
            job_id: job.job_id,
            job_class: job_class,
            queue: job.queue_name,
            error: error&.message
          })

          # === FLUX: Discard metrics ===
          send_to_flux(:increment, 'rails.jobs.discarded', 1, {
            job_class: job_class,
            queue: job.queue_name
          })

          # === RECALL: Log discard ===
          send_to_recall(:warn, "Job discarded", {
            job_id: job.job_id,
            job_class: job_class,
            error: error&.message
          })
        end

        def sanitize_job_arguments(arguments)
          return [] unless arguments.is_a?(Array)

          arguments.map do |arg|
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
