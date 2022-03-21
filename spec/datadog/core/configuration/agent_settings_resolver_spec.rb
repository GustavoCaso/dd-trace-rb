# typed: false

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Configuration::AgentSettingsResolver do
  around { |example| ClimateControl.modify(default_environment.merge(environment)) { example.run } }

  let(:default_environment) do
    {
      'DD_AGENT_HOST' => nil,
      'DD_TRACE_AGENT_PORT' => nil,
      'DD_TRACE_AGENT_URL' => nil
    }
  end
  let(:environment) { {} }
  let(:ddtrace_settings) { Datadog::Core::Configuration::Settings.new }
  let(:logger) { instance_double(Datadog::Core::Logger) }

  let(:settings) do
    {
      adapter: adapter,
      ssl: false,
      hostname: hostname,
      port: port,
      uds_path: uds_path,
      timeout_seconds: nil,
      deprecated_for_removal_transport_configuration_proc: nil,
    }
  end

  let(:adapter) { :net_http }
  let(:hostname) { '127.0.0.1' }
  let(:port) { 8126 }
  let(:uds_path) { nil }

  before do
    # Environment does not have existing unix socket for the base testing case
    allow(File).to receive(:exist?).with('/var/run/datadog/apm.socket').and_return(false)
  end

  subject(:resolver) { described_class.call(ddtrace_settings, logger: logger) }

  context 'by default' do
    it 'contacts the agent using the http adapter, using hostname 127.0.0.1 and port 8126' do
      expect(resolver).to have_attributes settings
    end

    context 'with default unix socket present' do
      before do
        expect(File).to receive(:exist?).with('/var/run/datadog/apm.socket').and_return(true)
      end

      let(:adapter) { :unix }
      let(:uds_path) { '/var/run/datadog/apm.socket' }
      let(:hostname) { nil }
      let(:port) { nil }

      it 'configures the agent to connect to unix:/var/run/datadog/apm.socket' do
        expect(resolver).to have_attributes settings
      end
    end
  end

  describe 'http adapter hostname' do
    context 'when a custom hostname is specified via the DD_AGENT_HOST environment variable' do
      let(:environment) { { 'DD_AGENT_HOST' => 'custom-hostname' } }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via code using "agent.host ="' do
      before do
        ddtrace_settings.agent.host = 'custom-hostname'
      end

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via the DD_TRACE_AGENT_URL environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => "http://custom-hostname:#{port}" } }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    describe 'priority' do
      let(:with_agent_host) { nil }
      let(:with_trace_agent_url) { nil }
      let(:with_environment_agent_host) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_URL'] = "http://#{with_trace_agent_url}:1234") if with_trace_agent_url
        (environment['DD_AGENT_HOST'] = with_environment_agent_host) if with_environment_agent_host

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (ddtrace_settings.agent.host = with_agent_host) if with_agent_host
      end

      context 'when all of agent.host, DD_TRACE_AGENT_URL, DD_AGENT_HOST are provided' do
        let(:with_agent_host) { 'custom-hostname-2' }
        let(:with_trace_agent_url) { 'custom-hostname-3' }
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'prioritizes the agent.port' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-2')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when DD_TRACE_AGENT_URL, DD_AGENT_HOST are provided' do
        let(:with_trace_agent_url) { 'custom-hostname-3' }
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'prioritizes the DD_TRACE_AGENT_URL' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-3')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      # This somewhat duplicates some of the testing above, but it's still helpful to validate that the test is correct
      # (otherwise it may pass due to bugs, not due to right priority being used)
      context 'when only DD_AGENT_HOST is provided' do
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'uses the DD_AGENT_HOST' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-4')
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  describe 'http adapter port' do
    context 'when a custom port is specified via the DD_TRACE_AGENT_PORT environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_PORT' => '1234' } }

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
      end

      context 'when the custom port is invalid' do
        let(:environment) { { 'DD_TRACE_AGENT_PORT' => 'this-is-an-invalid-port' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom port is specified via code using "agent.port = "' do
      before do
        ddtrace_settings.agent.port = 1234
      end

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
      end

      context 'when the port is specified as a string instead of a number' do
        before do
          ddtrace_settings.agent.port = '1234'
        end

        it 'contacts the agent using the http adapter, using the custom port' do
          expect(resolver).to have_attributes(**settings, port: 1234)
        end
      end

      context 'when the port is an invalid string value' do
        before do
          ddtrace_settings.agent.port = 'kaboom'

          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end

      context 'when the port is an invalid object' do
        before do
          ddtrace_settings.agent.port = Object.new

          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom port is specified via the DD_TRACE_AGENT_URL environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => "http://#{hostname}:1234" } }

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
      end
    end

    describe 'priority' do
      let(:with_agent_port) { nil }
      let(:with_trace_agent_url) { nil }
      let(:with_trace_agent_port) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_URL'] = "http://custom-hostname:#{with_trace_agent_url}") if with_trace_agent_url
        (environment['DD_TRACE_AGENT_PORT'] = with_trace_agent_port.to_s) if with_trace_agent_port

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (ddtrace_settings.agent.port = with_agent_port) if with_agent_port
      end

      context 'when all of agent.port, DD_TRACE_AGENT_URL, DD_TRACE_AGENT_PORT are provided' do
        let(:with_agent_port) { 2 }
        let(:with_trace_agent_url) { 3 }
        let(:with_trace_agent_port) { 4 }

        it 'prioritizes the agent.port' do
          expect(resolver).to have_attributes(port: 2)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when DD_TRACE_AGENT_URL, DD_TRACE_AGENT_PORT are provided' do
        let(:with_trace_agent_url) { 3 }
        let(:with_trace_agent_port) { 4 }

        it 'prioritizes the DD_TRACE_AGENT_URL' do
          expect(resolver).to have_attributes(port: 3)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      # This somewhat duplicates some of the testing above, but it's still helpful to validate that the test is correct
      # (otherwise it may pass due to bugs, not due to right priority being used)
      context 'when only DD_TRACE_AGENT_PORT is provided' do
        let(:with_trace_agent_port) { 4 }

        it 'uses the DD_TRACE_AGENT_PORT' do
          expect(resolver).to have_attributes(port: 4)
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  context 'when a custom url is specified via environment variable' do
    let(:environment) { { 'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234' } }

    it 'contacts the agent using the http adapter, using the custom hostname and port' do
      expect(resolver).to have_attributes(
        **settings,
        ssl: false,
        hostname: 'custom-hostname',
        port: 1234
      )
    end

    context 'when the uri scheme is https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'https://custom-hostname:1234' } }

      it 'contacts the agent using the http adapter, using ssl: true' do
        expect(resolver).to have_attributes(ssl: true)
      end
    end

    context 'when the uri scheme is not http OR https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'steam://custom-hostname:1234' } }

      before do
        allow(logger).to receive(:warn)
      end

      it 'falls back to the defaults' do
        expect(resolver).to have_attributes settings
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Invalid URI scheme/)

        resolver
      end
    end
  end

  context 'when a proc is configured in tracer.transport_options' do
    let(:deprecated_for_removal_transport_configuration_proc) { proc {} }

    before do
      ddtrace_settings.tracing.transport_options = deprecated_for_removal_transport_configuration_proc
    end

    it 'includes the given proc in the resolved settings as the deprecated_for_removal_transport_configuration_proc' do
      expect(resolver).to have_attributes(
        **settings,
        deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc
      )
    end
  end

  describe '#log_warning' do
    let(:message) { 'this is a test warning' }

    subject(:log_warning) do
      described_class.new(ddtrace_settings, logger: logger).send(:log_warning, message)
    end

    it 'logs a warning used the configured logger' do
      expect(logger).to receive(:warn).with('this is a test warning')

      log_warning
    end

    context 'when logger is nil' do
      let(:logger) { nil }

      it 'does not log anything' do
        log_warning
      end
    end
  end
end
