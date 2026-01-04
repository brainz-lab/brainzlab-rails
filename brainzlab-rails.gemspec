# frozen_string_literal: true

require_relative 'lib/brainzlab/rails/version'

Gem::Specification.new do |spec|
  spec.name          = 'brainzlab-rails'
  spec.version       = BrainzLab::Rails::VERSION
  spec.authors       = ['Brainz Lab']
  spec.email         = ['support@brainzlab.ai']

  spec.summary       = 'Rails-native observability powered by ActiveSupport::Notifications'
  spec.description   = 'Deep Rails instrumentation that routes events to Pulse (APM), Recall (Logs), Reflex (Errors), Flux (Metrics), and Nerve (Jobs). One gem, full Rails observability.'
  spec.homepage      = 'https://brainzlab.ai'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/brainz-lab/brainzlab-rails'
  spec.metadata['changelog_uri'] = 'https://github.com/brainz-lab/brainzlab-rails/blob/main/CHANGELOG.md'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'brainzlab', '>= 0.1.4'
  spec.add_dependency 'rails', '>= 7.0'
  spec.add_dependency 'activesupport', '>= 7.0'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-rails', '~> 6.0'
  spec.add_development_dependency 'rubocop', '~> 1.21'
end
