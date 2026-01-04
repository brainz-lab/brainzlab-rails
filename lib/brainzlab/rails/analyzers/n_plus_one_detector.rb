# frozen_string_literal: true

module BrainzLab
  module Rails
    module Analyzers
      # Detects N+1 query patterns by tracking similar queries within a request
      class NPlusOneDetector
        THRESHOLD = 3 # Minimum repeated queries to flag as N+1

        def initialize
          @query_tracker = {}
          @request_id = nil
        end

        def check(sql, name, unique_id)
          # Reset tracker on new request
          reset_if_new_request(unique_id)

          # Skip non-SELECT queries
          return nil unless sql.to_s.strip.upcase.start_with?('SELECT')

          # Skip SCHEMA queries
          return nil if name == 'SCHEMA'

          # Normalize query for comparison (remove specific values)
          normalized = normalize_query(sql)

          # Track query occurrences
          @query_tracker[normalized] ||= { count: 0, first_seen: Time.now, sql: sql }
          @query_tracker[normalized][:count] += 1

          # Check if threshold exceeded
          count = @query_tracker[normalized][:count]
          if count == THRESHOLD
            {
              query: truncate_sql(sql),
              normalized: normalized,
              count: count,
              model: extract_model_from_query(sql),
              location: extract_caller_location
            }
          else
            nil
          end
        end

        private

        def reset_if_new_request(unique_id)
          if @request_id != unique_id
            @request_id = unique_id
            @query_tracker = {}
          end
        end

        def normalize_query(sql)
          sql
            .gsub(/\d+/, '?')                          # Replace numbers with ?
            .gsub(/'[^']*'/, '?')                      # Replace strings with ?
            .gsub(/"[^"]*"/, '?')                      # Replace quoted strings with ?
            .gsub(/\s+/, ' ')                          # Normalize whitespace
            .strip
        end

        def extract_model_from_query(sql)
          # Try to extract table name from SELECT ... FROM table_name
          match = sql.match(/FROM\s+["`']?(\w+)["`']?/i)
          if match
            table_name = match[1]
            # Convert to likely model name
            table_name.singularize.camelize rescue table_name
          else
            'Unknown'
          end
        end

        def extract_caller_location
          # Find the first application frame in the backtrace
          caller.find do |frame|
            frame.include?('/app/') && !frame.include?('/gems/')
          end
        end

        def truncate_sql(sql, max_length = 200)
          sql.length > max_length ? "#{sql[0, max_length]}..." : sql
        end
      end
    end
  end
end
