# frozen_string_literal: true

require 'brainzlab'
require 'active_support'
require 'active_support/notifications'

require_relative 'brainzlab/rails/version'
require_relative 'brainzlab/rails/configuration'
require_relative 'brainzlab/rails/subscriber'
require_relative 'brainzlab/rails/event_router'

# Collectors
require_relative 'brainzlab/rails/collectors/base'
require_relative 'brainzlab/rails/collectors/action_controller'
require_relative 'brainzlab/rails/collectors/action_view'
require_relative 'brainzlab/rails/collectors/active_record'
require_relative 'brainzlab/rails/collectors/active_job'
require_relative 'brainzlab/rails/collectors/action_cable'
require_relative 'brainzlab/rails/collectors/action_mailer'
require_relative 'brainzlab/rails/collectors/active_storage'
require_relative 'brainzlab/rails/collectors/cache'

# Analyzers
require_relative 'brainzlab/rails/analyzers/n_plus_one_detector'
require_relative 'brainzlab/rails/analyzers/slow_query_analyzer'
require_relative 'brainzlab/rails/analyzers/cache_efficiency'

# Railtie for auto-initialization
require_relative 'brainzlab/rails/railtie' if defined?(::Rails::Railtie)

module BrainzLab
  module Rails
    class << self
      attr_accessor :configuration

      def configure
        self.configuration ||= Configuration.new
        yield(configuration) if block_given?
        configuration
      end

      def subscriber
        @subscriber ||= Subscriber.new(configuration)
      end

      def start!
        return if @started

        subscriber.subscribe_all!
        @started = true
        BrainzLab.debug_log('[BrainzLab::Rails] Started instrumentation')
      end

      def stop!
        return unless @started

        subscriber.unsubscribe_all!
        @started = false
        BrainzLab.debug_log('[BrainzLab::Rails] Stopped instrumentation')
      end

      def started?
        @started == true
      end
    end
  end
end
