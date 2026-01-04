# frozen_string_literal: true

module BrainzLab
  module Rails
    # Routes Rails instrumentation events to appropriate BrainzLab products
    # Each event can be sent to multiple products based on its type
    class EventRouter
      attr_reader :configuration, :collectors

      def initialize(configuration)
        @configuration = configuration
        @collectors = initialize_collectors
      end

      def route(event_data)
        event_name = event_data[:name]
        collector = collector_for(event_name)

        return unless collector

        # Collector processes and routes to products
        collector.process(event_data)
      end

      private

      def initialize_collectors
        {
          action_controller: Collectors::ActionController.new(@configuration),
          action_view: Collectors::ActionView.new(@configuration),
          active_record: Collectors::ActiveRecord.new(@configuration),
          active_job: Collectors::ActiveJob.new(@configuration),
          action_cable: Collectors::ActionCable.new(@configuration),
          action_mailer: Collectors::ActionMailer.new(@configuration),
          active_storage: Collectors::ActiveStorage.new(@configuration),
          cache: Collectors::Cache.new(@configuration)
        }
      end

      def collector_for(event_name)
        case event_name
        when /\.action_controller$/
          @collectors[:action_controller] if @configuration.action_controller_enabled
        when /\.action_view$/
          @collectors[:action_view] if @configuration.action_view_enabled
        when /\.active_record$/
          @collectors[:active_record] if @configuration.active_record_enabled
        when /\.active_job$/
          @collectors[:active_job] if @configuration.active_job_enabled
        when /\.action_cable$/
          @collectors[:action_cable] if @configuration.action_cable_enabled
        when /\.action_mailer$/, /\.action_mailbox$/
          @collectors[:action_mailer] if @configuration.action_mailer_enabled
        when /\.active_storage$/
          @collectors[:active_storage] if @configuration.active_storage_enabled
        when /cache.*\.active_support$/, /message_serializer_fallback\.active_support$/
          @collectors[:cache] if @configuration.cache_enabled
        when /\.action_dispatch$/
          @collectors[:action_controller] if @configuration.action_controller_enabled
        when /deprecation\.rails$/, /\.railties$/
          # Route deprecations to Recall for logging
          @collectors[:action_controller] if @configuration.action_controller_enabled
        end
      end
    end
  end
end
