# frozen_string_literal: true

require 'rails/generators/base'

module Brainzlab
  class InstallGenerator < ::Rails::Generators::Base
    source_root File.expand_path('install/templates', __dir__)

    desc 'Creates a BrainzLab Rails initializer with zero-config setup'

    class_option :key, type: :string, desc: 'Your BrainzLab secret key (optional with zero-config)'
    class_option :credentials, type: :boolean, default: true, desc: 'Add key to Rails credentials instead of ENV'
    class_option :minimal, type: :boolean, default: false, desc: 'Generate minimal config (rely on auto-detection)'

    def copy_initializer
      template 'brainzlab.rb.tt', 'config/initializers/brainzlab.rb'
    end

    def show_credentials_instructions
      return unless options[:credentials] && options[:key].blank?

      say ''
      say 'Zero-Config Setup', :green
      say '=' * 50
      say ''
      say 'BrainzLab Rails supports zero-config setup!', :green
      say 'Just add your secret key to Rails credentials:'
      say ''
      say '  EDITOR="code --wait" bin/rails credentials:edit', :yellow
      say ''
      say 'Add the following:'
      say ''
      say '  brainzlab:', :cyan
      say '    secret_key: your_secret_key_here', :cyan
      say ''
      say 'Or for auto-provisioning (recommended):'
      say ''
      say '  brainzlab:', :cyan
      say '    recall_master_key: your_recall_master_key', :cyan
      say '    reflex_master_key: your_reflex_master_key', :cyan
      say '    pulse_master_key: your_pulse_master_key', :cyan
      say ''
      say 'Get your keys at: https://brainzlab.ai/dashboard', :blue
      say ''
    end

    def show_env_alternative
      say ''
      say 'Alternative: Environment Variables', :yellow
      say '-' * 50
      say ''
      say 'You can also use environment variables:'
      say ''
      say '  export BRAINZLAB_SECRET_KEY=your_key_here', :cyan
      say ''
      say 'Or for auto-provisioning:'
      say ''
      say '  export RECALL_MASTER_KEY=your_recall_master_key', :cyan
      say '  export REFLEX_MASTER_KEY=your_reflex_master_key', :cyan
      say '  export PULSE_MASTER_KEY=your_pulse_master_key', :cyan
      say ''
    end

    def show_auto_detection_info
      say ''
      say 'Auto-Detection', :green
      say '-' * 50
      say ''
      say 'BrainzLab Rails automatically detects:'
      say ''
      say "  - environment:   Rails.env (#{detect_environment})", :cyan
      say "  - service_name:  #{detect_service_name || 'your-app-name'}", :cyan
      say "  - hostname:      Socket.gethostname", :cyan
      say ''
      say 'No configuration needed for these values!', :green
      say ''
    end

    def show_final_message
      say ''
      say 'Installation Complete!', :green
      say '=' * 50
      say ''
      say 'What happens now:'
      say '  1. Set your secret key (credentials or ENV)'
      say '  2. Start your Rails server'
      say '  3. BrainzLab automatically instruments your app'
      say ''
      say 'Documentation: https://docs.brainzlab.ai/rails', :blue
      say ''
    end

    private

    def secret_key_value
      if options[:key].present?
        %("#{options[:key]}")
      else
        '# Auto-detected from Rails credentials or ENV'
      end
    end

    def app_name
      ::Rails.application.class.module_parent_name.underscore.tr('_', '-')
    rescue StandardError
      'my-app'
    end

    def detect_environment
      ::Rails.env.to_s
    rescue StandardError
      'development'
    end

    def detect_service_name
      ::Rails.application.class.module_parent_name.underscore.tr('_', '-')
    rescue StandardError
      nil
    end

    def minimal_config?
      options[:minimal]
    end
  end
end
