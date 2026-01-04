# BrainzLab Rails Instrumentation - Implementation Plan

## Overview

This document outlines the complete implementation plan for the `brainzlab-rails` gem and required enhancements to the BrainzLab ecosystem.

## Current State

### Completed (Phase 1)

- [x] **Gem Structure** - Created `brainzlab-rails` gem with proper gemspec
- [x] **Subscriber** - Implemented `monotonic_subscribe` for accurate timing
- [x] **Event Router** - Routes 64+ Rails events to appropriate products
- [x] **Collectors** - All 8 collectors implemented:
  - ActionController (12 events)
  - ActionView (4 events)
  - ActiveRecord (5 events)
  - ActiveJob (8 events)
  - ActionCable (5 events)
  - ActionMailer (3 events)
  - ActiveStorage (12 events)
  - Cache (15 events)
- [x] **Analyzers** - Three intelligent analyzers:
  - N+1 Query Detector
  - Slow Query Analyzer
  - Cache Efficiency Tracker
- [x] **Railtie** - Auto-initialization in Rails apps

---

## Phase 2: SDK Enhancements

### 2.1 Enhanced Pulse Methods

Add specialized APM methods to the BrainzLab SDK:

```ruby
# lib/brainzlab/pulse.rb
module BrainzLab
  module Pulse
    class << self
      # Record a span with structured attributes
      def record_span(name:, duration_ms:, category:, attributes: {}, timestamp: nil)
        # Implementation
      end

      # Start a trace context
      def start_trace(name, attributes = {})
        # Returns trace context
      end

      # End current trace
      def end_trace(trace_context)
        # Finalizes and sends trace
      end
    end
  end
end
```

**Files to modify:**
- `lib/brainzlab/pulse.rb` (add `record_span`, `start_trace`, `end_trace`)
- `lib/brainzlab/pulse/span.rb` (new - span data structure)
- `lib/brainzlab/pulse/trace.rb` (new - trace context)

### 2.2 Enhanced Flux Methods

Add metric methods to the SDK:

```ruby
# lib/brainzlab/flux.rb
module BrainzLab
  module Flux
    class << self
      def increment(metric, value = 1, tags: {})
      def gauge(metric, value, tags: {})
      def histogram(metric, value, tags: {})
      def timing(metric, value_ms, tags: {})
    end
  end
end
```

**Files to modify:**
- `lib/brainzlab/flux.rb` (new module)
- `lib/brainzlab/flux/client.rb` (metrics client)
- `lib/brainzlab/flux/buffer.rb` (metric batching)

### 2.3 Configuration Updates

```ruby
# lib/brainzlab/configuration.rb
# Add:
attr_accessor :flux_enabled
attr_accessor :flux_url
attr_accessor :flux_api_key

def flux_effectively_enabled?
  flux_enabled && flux_url.present?
end
```

---

## Phase 3: Server-Side Enhancements

### 3.1 Pulse Dashboard Updates

The Pulse server needs to handle structured span data:

**New API Endpoints:**
```
POST /api/v1/spans         - Ingest spans with attributes
GET  /api/v1/traces/:id    - Get trace with spans
GET  /api/v1/requests      - Request list with breakdown
```

**Database Schema:**
```ruby
create_table :spans do |t|
  t.references :trace, null: false
  t.string :name, null: false
  t.string :category
  t.float :duration_ms
  t.jsonb :attributes, default: {}
  t.datetime :started_at
  t.datetime :finished_at
  t.timestamps
end

create_table :traces do |t|
  t.references :project, null: false
  t.string :trace_id, null: false
  t.string :name
  t.float :total_duration_ms
  t.jsonb :metadata, default: {}
  t.timestamps
end
```

**Dashboard Features:**
- Request waterfall (like Chrome DevTools)
- SQL query breakdown with timing
- View rendering breakdown
- N+1 alerts
- Slow query highlighting

### 3.2 Flux Product (New)

If Flux doesn't exist, create it:

**Key Features:**
- Time-series metrics storage (TimescaleDB)
- Real-time dashboards
- Custom metric definitions
- Anomaly detection
- Alerting integration

**Models:**
```ruby
# Metric definition
class Metric < ApplicationRecord
  belongs_to :project
  has_many :data_points
end

# Time-series data (TimescaleDB hypertable)
class DataPoint < ApplicationRecord
  belongs_to :metric
  # time, value, tags (jsonb)
end
```

### 3.3 Recall Enhancements

**Structured Log Filtering:**
- Filter by Rails event type
- Filter by controller/action
- Filter by job class
- Search by payload attributes

**UI Updates:**
- Event type badges
- Expandable payload viewer
- Request correlation view

### 3.4 Reflex Enhancements

**Breadcrumb Improvements:**
- Group by category (db, http, cache, job)
- Timeline visualization
- SQL queries before error
- Cache state at error time

**Error Context:**
- Attach request breakdown
- Show N+1 warnings
- Include slow queries

---

## Phase 4: Advanced Features

### 4.1 N+1 Query Dashboard

Dedicated view for N+1 detection:

```
/dashboard/performance/n-plus-one

Features:
- List of detected N+1 patterns
- Query frequency
- Affected controllers/actions
- Fix suggestions (eager loading)
- Track resolution status
```

### 4.2 Slow Query Analysis

```
/dashboard/performance/slow-queries

Features:
- Slow query log with EXPLAIN
- Index recommendations
- Query patterns
- Performance trends
```

### 4.3 Cache Efficiency Dashboard

```
/dashboard/performance/cache

Features:
- Overall hit rate
- Per-key statistics
- Miss patterns
- TTL analysis
- Size tracking
```

### 4.4 Action Cable Monitor (Unique Differentiator)

```
/dashboard/websockets

Features:
- Active connections
- Subscription health
- Broadcast latency
- Message throughput
- Channel performance
```

---

## Phase 5: Testing & Documentation

### 5.1 Test Suite

```ruby
# spec/brainzlab/rails/subscriber_spec.rb
# spec/brainzlab/rails/event_router_spec.rb
# spec/brainzlab/rails/collectors/*_spec.rb
# spec/brainzlab/rails/analyzers/*_spec.rb
```

### 5.2 Integration Tests

```ruby
# Test with real Rails app
# Verify all 64+ events are captured
# Verify accurate timing with monotonic_subscribe
# Test sampling
# Test filtering
```

### 5.3 Documentation

- README with quick start
- Configuration reference
- Event reference (all 64+ events)
- Dashboard usage guide
- Troubleshooting guide

---

## Implementation Priority

### Week 1: Core SDK
1. [ ] Add `Pulse.record_span` to SDK
2. [ ] Add `Flux` module to SDK
3. [ ] Update SDK configuration
4. [ ] Publish SDK v0.1.5

### Week 2: Gem Polish
1. [ ] Add comprehensive tests
2. [ ] Validate all event handlers
3. [ ] Performance benchmarking
4. [ ] Publish gem v0.1.0

### Week 3: Pulse Updates
1. [ ] Span ingestion API
2. [ ] Trace aggregation
3. [ ] Request waterfall UI
4. [ ] N+1 detection UI

### Week 4: Additional Products
1. [ ] Flux metric ingestion
2. [ ] Recall structured logs UI
3. [ ] Reflex breadcrumb improvements
4. [ ] Action Cable dashboard

---

## Event → Product Matrix

| Rails Event | Pulse | Recall | Reflex | Flux | Nerve |
|-------------|-------|--------|--------|------|-------|
| process_action.action_controller | ✓ | ✓ | ✓* | ✓ | |
| sql.active_record | ✓ | | | ✓ | |
| render_*.action_view | ✓ | | | ✓ | |
| *.active_job | ✓ | ✓ | ✓* | ✓ | ✓ |
| *.action_cable | ✓ | ✓ | ✓* | ✓ | |
| cache_*.active_support | ✓ | | | ✓ | |
| deliver.action_mailer | ✓ | ✓ | ✓* | ✓ | |
| service_*.active_storage | ✓ | ✓ | | ✓ | |

*✓ = Only when exception in payload*

---

## Success Metrics

1. **Coverage**: 100% of Rails instrumentation events captured
2. **Accuracy**: < 1ms timing variance vs wall-clock
3. **Performance**: < 5% overhead in production
4. **Adoption**: Zero-config installation via Railtie
5. **Insights**: Automatic N+1 detection, slow query analysis

---

## Competitive Advantage

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   THEM (Datadog/New Relic):                                    │
│   - Generic agents that monkey-patch                           │
│   - "HTTP 200 in 234ms"                                        │
│   - Separate products, separate billing                        │
│                                                                 │
│   US (BrainzLab):                                              │
│   - Native Rails via ActiveSupport::Notifications             │
│   - "PostsController#index: 4 queries (N+1!), 3 cache hits"   │
│   - One gem, all products, Rails-optimized                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Next Steps

1. **Immediate**: Add Pulse.record_span to SDK
2. **This Week**: Publish brainzlab-rails gem v0.1.0
3. **Next Week**: Update Pulse dashboard for spans
4. **Future**: Build Action Cable dashboard (differentiator)
