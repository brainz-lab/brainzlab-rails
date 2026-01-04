# frozen_string_literal: true

module BrainzLab
  module Rails
    module Analyzers
      # Analyzes slow queries and provides optimization suggestions
      class SlowQueryAnalyzer
        def initialize(configuration)
          @configuration = configuration
          @slow_queries = []
        end

        def analyze(sql, duration_ms, payload)
          query_info = {
            sql: truncate_sql(sql),
            duration_ms: duration_ms,
            name: payload[:name],
            timestamp: Time.now.utc,
            suggestions: generate_suggestions(sql, payload)
          }

          # Log slow query
          log_slow_query(query_info)

          # Track for reporting
          @slow_queries << query_info

          query_info
        end

        def recent_slow_queries(limit = 10)
          @slow_queries.last(limit)
        end

        def clear!
          @slow_queries = []
        end

        private

        def generate_suggestions(sql, payload)
          suggestions = []

          # Check for missing index indicators
          if sql.include?('WHERE') && !sql.include?('INDEX')
            suggestions << 'Consider adding an index for the WHERE clause columns'
          end

          # Check for SELECT *
          if sql.match?(/SELECT\s+\*/i)
            suggestions << 'Avoid SELECT * - specify only needed columns'
          end

          # Check for large LIMIT
          if sql.match?(/LIMIT\s+(\d+)/i) && Regexp.last_match(1).to_i > 1000
            suggestions << 'Large LIMIT detected - consider pagination'
          end

          # Check for ORDER BY without LIMIT
          if sql.include?('ORDER BY') && !sql.include?('LIMIT')
            suggestions << 'ORDER BY without LIMIT may be slow on large tables'
          end

          # Check for multiple JOINs
          join_count = sql.scan(/JOIN/i).size
          if join_count > 3
            suggestions << "#{join_count} JOINs detected - consider query optimization"
          end

          # Check for subqueries
          if sql.scan(/SELECT/i).size > 1
            suggestions << 'Subquery detected - consider using JOINs or CTEs'
          end

          # Check for LIKE with leading wildcard
          if sql.match?(/LIKE\s+['"]%/i)
            suggestions << 'Leading wildcard in LIKE prevents index usage'
          end

          # Check for OR in WHERE
          if sql.match?(/WHERE.*\bOR\b/i)
            suggestions << 'OR in WHERE clause may prevent index usage - consider UNION'
          end

          suggestions
        end

        def log_slow_query(query_info)
          if BrainzLab.configuration&.recall_effectively_enabled?
            BrainzLab::Recall.warn('Slow query detected', **{
              sql: query_info[:sql],
              duration_ms: query_info[:duration_ms],
              name: query_info[:name],
              suggestions: query_info[:suggestions]
            })
          end

          if BrainzLab.configuration&.reflex_effectively_enabled?
            BrainzLab::Reflex.add_breadcrumb(
              "Slow query: #{query_info[:duration_ms]}ms",
              category: 'db.slow_query',
              level: :warning,
              data: {
                sql: query_info[:sql],
                duration_ms: query_info[:duration_ms],
                suggestions: query_info[:suggestions]
              }
            )
          end
        end

        def truncate_sql(sql, max_length = 500)
          sql.length > max_length ? "#{sql[0, max_length]}..." : sql
        end
      end
    end
  end
end
