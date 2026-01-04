# frozen_string_literal: true

module BrainzLab
  module Rails
    module Collectors
      # Collects Active Record database events
      # Provides deep database observability including N+1 detection
      class ActiveRecord < Base
        def initialize(configuration)
          super
          @n_plus_one_detector = Analyzers::NPlusOneDetector.new
          @slow_query_analyzer = Analyzers::SlowQueryAnalyzer.new(configuration)
        end

        def process(event_data)
          case event_data[:name]
          when 'sql.active_record'
            handle_sql(event_data)
          when 'instantiation.active_record'
            handle_instantiation(event_data)
          when 'start_transaction.active_record'
            handle_start_transaction(event_data)
          when 'transaction.active_record'
            handle_transaction(event_data)
          when 'strict_loading_violation.active_record'
            handle_strict_loading_violation(event_data)
          end
        end

        private

        def handle_sql(event_data)
          payload = event_data[:payload]
          sql = payload[:sql]
          name = payload[:name]
          duration_ms = event_data[:duration_ms]

          # Skip ignored SQL patterns (schema queries, etc.)
          return if @configuration.ignored_sql?(sql)

          # Skip SCHEMA and internal queries for metrics
          return if name == 'SCHEMA' || name.nil?

          cached = payload[:cached] == true
          async = payload[:async] == true

          # === N+1 Detection ===
          if @configuration.n_plus_one_detection
            n_plus_one = @n_plus_one_detector.check(sql, name, event_data[:unique_id])
            if n_plus_one
              handle_n_plus_one_detected(n_plus_one, event_data)
            end
          end

          # === Slow Query Analysis ===
          if @configuration.slow_query_threshold_ms && duration_ms > @configuration.slow_query_threshold_ms
            @slow_query_analyzer.analyze(sql, duration_ms, payload)
          end

          # === PULSE: Database span ===
          send_to_pulse(event_data, {
            name: "sql.#{extract_operation(sql)}",
            category: 'db.sql',
            attributes: {
              name: name,
              sql: truncate_sql(sql),
              cached: cached,
              async: async,
              row_count: payload[:row_count],
              affected_rows: payload[:affected_rows]
            }
          })

          # === FLUX: Metrics ===
          operation = extract_operation(sql)
          tags = { operation: operation, cached: cached }

          send_to_flux(:increment, 'rails.db.queries', 1, tags)
          send_to_flux(:timing, 'rails.db.query_ms', duration_ms, tags)

          if cached
            send_to_flux(:increment, 'rails.db.cache_hits', 1)
          end

          if payload[:row_count]
            send_to_flux(:histogram, 'rails.db.rows_returned', payload[:row_count], tags)
          end

          # === REFLEX: Breadcrumb ===
          add_breadcrumb(
            "#{name}: #{truncate_sql(sql, 100)}",
            category: 'db.query',
            level: :debug,
            data: {
              duration_ms: duration_ms,
              cached: cached,
              operation: operation
            }
          )
        end

        def handle_n_plus_one_detected(detection, event_data)
          # === RECALL: Log N+1 warning ===
          send_to_recall(:warn, "N+1 query detected", {
            query: detection[:query],
            count: detection[:count],
            model: detection[:model],
            location: detection[:location]
          })

          # === REFLEX: Add warning breadcrumb ===
          add_breadcrumb(
            "N+1 detected: #{detection[:model]} (#{detection[:count]} queries)",
            category: 'db.n_plus_one',
            level: :warning,
            data: detection
          )

          # === FLUX: Track N+1 occurrences ===
          send_to_flux(:increment, 'rails.db.n_plus_one', 1, {
            model: detection[:model]
          })
        end

        def handle_instantiation(event_data)
          payload = event_data[:payload]
          record_count = payload[:record_count]
          class_name = payload[:class_name]

          # === PULSE: Instantiation span ===
          send_to_pulse(event_data, {
            name: "instantiate.#{class_name}",
            category: 'db.instantiation',
            attributes: {
              class_name: class_name,
              record_count: record_count
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:histogram, 'rails.db.records_instantiated', record_count, {
            model: class_name
          })

          # Flag large instantiations (potential memory issue)
          if record_count > 1000
            send_to_recall(:warn, "Large record instantiation", {
              model: class_name,
              record_count: record_count
            })
          end
        end

        def handle_start_transaction(event_data)
          add_breadcrumb(
            "Transaction started",
            category: 'db.transaction',
            level: :debug,
            data: {}
          )

          send_to_flux(:increment, 'rails.db.transactions_started', 1)
        end

        def handle_transaction(event_data)
          payload = event_data[:payload]
          outcome = payload[:outcome]
          duration_ms = event_data[:duration_ms]

          # === PULSE: Transaction span ===
          send_to_pulse(event_data, {
            name: "transaction.#{outcome}",
            category: 'db.transaction',
            attributes: {
              outcome: outcome
            }
          })

          # === FLUX: Metrics ===
          send_to_flux(:increment, "rails.db.transactions.#{outcome}", 1)
          send_to_flux(:timing, 'rails.db.transaction_ms', duration_ms, {
            outcome: outcome
          })

          # === REFLEX: Breadcrumb ===
          level = outcome == :rollback ? :warning : :debug
          add_breadcrumb(
            "Transaction #{outcome}",
            category: 'db.transaction',
            level: level,
            data: {
              outcome: outcome,
              duration_ms: duration_ms
            }
          )

          # Log rollbacks as warnings
          if outcome == :rollback
            send_to_recall(:warn, "Transaction rolled back", {
              duration_ms: duration_ms
            })
          end
        end

        def handle_strict_loading_violation(event_data)
          payload = event_data[:payload]
          owner = payload[:owner]
          reflection = payload[:reflection]

          send_to_recall(:warn, "Strict loading violation", {
            owner: owner.to_s,
            association: reflection.to_s
          })

          add_breadcrumb(
            "Strict loading: #{owner} -> #{reflection}",
            category: 'db.strict_loading',
            level: :warning,
            data: {
              owner: owner.to_s,
              association: reflection.to_s
            }
          )

          send_to_flux(:increment, 'rails.db.strict_loading_violations', 1)
        end

        def extract_operation(sql)
          case sql.to_s.strip.upcase
          when /\ASELECT/i then 'SELECT'
          when /\AINSERT/i then 'INSERT'
          when /\AUPDATE/i then 'UPDATE'
          when /\ADELETE/i then 'DELETE'
          when /\ABEGIN/i then 'BEGIN'
          when /\ACOMMIT/i then 'COMMIT'
          when /\AROLLBACK/i then 'ROLLBACK'
          when /\ASAVEPOINT/i then 'SAVEPOINT'
          else 'OTHER'
          end
        end

        def truncate_sql(sql, max_length = 500)
          return '' if sql.nil?

          sql.length > max_length ? "#{sql[0, max_length]}..." : sql
        end
      end
    end
  end
end
