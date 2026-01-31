# BrainzLab Rails

Rails-native observability powered by ActiveSupport::Notifications.

[![Gem Version](https://badge.fury.io/rb/brainzlab-rails.svg)](https://rubygems.org/gems/brainzlab-rails)
[![License: OSAaSy](https://img.shields.io/badge/License-OSAaSy-blue.svg)](LICENSE)

## Quick Start

```ruby
# Gemfile
gem 'brainzlab-rails'

# config/initializers/brainzlab.rb
BrainzLab.configure do |config|
  config.secret_key = ENV['BRAINZLAB_SECRET_KEY']
end

# That's it! Auto-starts via Railtie
```

## Installation

Add to your Gemfile:

```ruby
gem 'brainzlab-rails'
```

Then run:

```bash
bundle install
rails g brainzlab:install
```

## Configuration

### Zero-Config Setup

BrainzLab Rails supports true zero-config operation. Just add your secret key:

**Option 1: Rails Credentials (Recommended)**

```bash
EDITOR="code --wait" bin/rails credentials:edit
```

Add:

```yaml
brainzlab:
  secret_key: your_secret_key_here
```

**Option 2: Environment Variables**

```bash
export BRAINZLAB_SECRET_KEY=your_secret_key_here
```

### Rails-Specific Configuration

```ruby
# config/application.rb
Rails.application.configure do
  config.brainzlab_rails.n_plus_one_detection = true
  config.brainzlab_rails.slow_query_threshold_ms = 100
  config.brainzlab_rails.sample_rate = 1.0
  config.brainzlab_rails.ignored_actions = ['HealthController#check']
end
```

### Full Configuration

```ruby
# config/initializers/brainzlab.rb
BrainzLab.configure do |config|
  # Products (all enabled by default)
  config.recall_enabled = true  # Logging
  config.reflex_enabled = true  # Error tracking
  config.pulse_enabled = true   # APM/Tracing
  config.flux_enabled = true    # Metrics

  # Filtering
  config.scrub_fields = %i[password token api_key secret]

  # Error exclusions
  config.reflex_excluded_exceptions = [
    'ActionController::RoutingError',
    'ActiveRecord::RecordNotFound'
  ]
end
```

## Usage

### What Gets Instrumented

| Component | Events | Description |
|-----------|--------|-------------|
| Action Controller | 12 events | Requests, redirects, filters, CSRF, caching |
| Action View | 4 events | Template rendering, partials, collections |
| Active Record | 5 events | SQL queries, transactions, connections |
| Active Job | 8 events | Enqueue, perform, retry, discard, exceptions |
| Action Cable | 5 events | WebSocket connections, subscriptions, broadcasts |
| Action Mailer | 3 events | Email delivery, generation |
| Active Storage | 12 events | Uploads, downloads, transformations |
| Cache | 15 events | Reads, writes, deletes, expiration |
| **Total** | **64+ events** | Automatically instrumented |

### Smart Event Routing

Each Rails event is automatically routed to appropriate products:

| Product | Event Types |
|---------|-------------|
| **Pulse** | APM spans for all performance-critical events |
| **Recall** | Structured logs for requests, jobs, emails |
| **Reflex** | Breadcrumbs and error context |
| **Flux** | Metrics (counters, histograms, timing) |

### Built-in Analyzers

**N+1 Query Detection**

```ruby
# Detected automatically!
User.all.each { |user| user.posts.count }
# => Warning: N+1 query detected for Post (called 100 times)
```

**Slow Query Analyzer**

```ruby
config.brainzlab_rails.slow_query_threshold_ms = 100
```

**Cache Efficiency Tracking**

```ruby
BrainzLab::Rails.subscriber.event_router.collectors[:cache].hit_rate
# => 85.2
```

### View Helpers

```erb
<head>
  <%= brainzlab_js_tag %>
</head>
```

## API Reference

The gem automatically instruments all Rails events. No manual API calls required.

### Architecture

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

Full documentation: [docs.brainzlab.ai/rails](https://docs.brainzlab.ai/rails)

## Self-Hosting

For self-hosted installations, configure the SDK endpoints:

```ruby
BrainzLab.configure do |config|
  config.secret_key = ENV['BRAINZLAB_SECRET_KEY']
  config.recall_url = 'https://recall.your-domain.com'
  config.reflex_url = 'https://reflex.your-domain.com'
  config.pulse_url = 'https://pulse.your-domain.com'
end
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup.

### Development

```bash
bundle install
bundle exec rspec
gem build brainzlab-rails.gemspec
```

### Requirements

- Ruby >= 3.1.0
- Rails >= 7.0
- brainzlab gem >= 0.1.6

## Related

- [brainzlab](https://github.com/brainz-lab/brainzlab-ruby) - Core Ruby SDK
- [Recall](https://github.com/brainz-lab/recall) - Logging service
- [Reflex](https://github.com/brainz-lab/reflex) - Error tracking
- [Pulse](https://github.com/brainz-lab/pulse) - APM

## License

OSAaSy License - see [LICENSE](LICENSE) for details.
