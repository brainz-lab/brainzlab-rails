# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: BrainzLab Rails Instrumentation

Rails-native observability powered by ActiveSupport::Notifications. This gem hooks into ALL Rails instrumentation events and routes them intelligently to BrainzLab products.

**Gem**: brainzlab-rails (on RubyGems.org)

**GitHub**: brainz-lab/brainzlab-rails

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    BRAINZLAB-RAILS GEM                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              ActiveSupport::Notifications                 │  │
│  │         (monotonic_subscribe for accurate timing)         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Event Router                           │  │
│  │           Routes events to appropriate products           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│        ┌─────────────────────┼─────────────────────┐           │
│        │                     │                     │           │
│        ▼                     ▼                     ▼           │
│  ┌──────────┐         ┌──────────┐         ┌──────────┐       │
│  │Collectors│         │Collectors│         │Analyzers │       │
│  │  AC, AV  │         │  AR, AJ  │         │  N+1,    │       │
│  │  Cable   │         │ Mailer   │         │SlowQuery │       │
│  └──────────┘         └──────────┘         └──────────┘       │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   BrainzLab SDK                           │  │
│  │           Pulse • Recall • Reflex • Flux                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
lib/
├── brainzlab-rails.rb          # Main entry point
└── brainzlab/
    └── rails/
        ├── version.rb
        ├── configuration.rb    # Gem configuration
        ├── subscriber.rb       # Event subscription (monotonic)
        ├── event_router.rb     # Routes events to collectors
        ├── railtie.rb          # Rails auto-initialization
        ├── collectors/         # Event processors
        │   ├── base.rb
        │   ├── action_controller.rb
        │   ├── action_view.rb
        │   ├── active_record.rb
        │   ├── active_job.rb
        │   ├── action_cable.rb
        │   ├── action_mailer.rb
        │   ├── active_storage.rb
        │   └── cache.rb
        └── analyzers/          # Intelligent analysis
            ├── n_plus_one_detector.rb
            ├── slow_query_analyzer.rb
            └── cache_efficiency.rb
```

## Key Features

### 1. Monotonic Subscribe
Uses `ActiveSupport::Notifications.monotonic_subscribe` for accurate timing instead of wall-clock time.

### 2. Smart Event Routing
Each Rails event is routed to appropriate products:
- **Pulse**: APM spans for all performance-critical events
- **Recall**: Structured logs for requests, jobs, emails
- **Reflex**: Breadcrumbs and error context
- **Flux**: Metrics (counters, histograms, timing)
- **Nerve**: Job-specific monitoring

### 3. Built-in Analyzers
- **N+1 Detection**: Automatically detects repeated queries
- **Slow Query Analyzer**: Identifies slow queries with suggestions
- **Cache Efficiency**: Tracks hit rates and efficiency

## Rails Events Covered

| Component | Events |
|-----------|--------|
| Action Controller | 12 events |
| Action View | 4 events |
| Active Record | 5 events |
| Active Job | 8 events |
| Action Cable | 5 events |
| Action Mailer | 3 events |
| Active Storage | 12 events |
| Cache | 15 events |
| **Total** | **64+ events** |

## Usage

```ruby
# Gemfile
gem 'brainzlab-rails'
```

```bash
# Install with generator
bundle install
rails g brainzlab:install
```

### Zero-Config Setup

BrainzLab Rails supports true zero-config. Just add your key to Rails credentials:

```bash
EDITOR="code --wait" bin/rails credentials:edit
```

```yaml
brainzlab:
  secret_key: your_secret_key_here
```

**That's it!** BrainzLab Rails automatically detects:
- `environment` from `Rails.env`
- `service_name` from `Rails.application.class.module_parent_name`
- `hostname` from `Socket.gethostname`

### Configuration Sources (Priority Order)

1. **Environment variables**: `BRAINZLAB_SECRET_KEY`, `RECALL_MASTER_KEY`, etc.
2. **Rails credentials**: `Rails.application.credentials.brainzlab[:secret_key]`
3. **Auto-detection**: environment, service name, hostname

## Configuration

```ruby
# config/application.rb
config.brainzlab_rails.n_plus_one_detection = true
config.brainzlab_rails.slow_query_threshold_ms = 100
config.brainzlab_rails.sample_rate = 1.0
config.brainzlab_rails.ignored_actions = ['HealthController#check']
```

## Common Commands

```bash
bundle install
bundle exec rspec
gem build brainzlab-rails.gemspec
gem push brainzlab-rails-*.gem
```

## Dependencies

- `brainzlab` gem (>= 0.1.4)
- `rails` (>= 7.0)
- `activesupport` (>= 7.0)
