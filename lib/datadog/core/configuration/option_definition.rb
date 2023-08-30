# frozen_string_literal: true

require_relative 'option'

module Datadog
  module Core
    module Configuration
      # Represents a definition for an integration configuration option
      class OptionDefinition
        IDENTITY = ->(new_value, _old_value) { new_value }

        attr_reader \
          :default,
          :default_proc,
          :env,
          :deprecated_env,
          :env_parser,
          :name,
          :on_set,
          :resetter,
          :setter,
          :type,
          :type_options

        def initialize(name, meta = {}, &block)
          @default = meta[:default]
          @default_proc = meta[:default_proc]
          @env = meta[:env]
          @deprecated_env = meta[:deprecated_env]
          @env_parser = meta[:env_parser]
          @name = name.to_sym
          @on_set = meta[:on_set]
          @resetter = meta[:resetter]
          @setter = meta[:setter] || block || IDENTITY
          @type = meta[:type]
          @type_options = meta[:type_options]
        end

        # Creates a new Option, bound to the context provided.
        def build(context)
          Option.new(self, context)
        end

        # Acts as DSL for building OptionDefinitions
        # @public_api
        class Builder
          class InvalidOptionError < StandardError; end

          attr_reader \
            :helpers

          def initialize(name, options = {})
            @env = nil
            @deprecated_env = nil
            @env_parser = nil
            @default = nil
            @default_proc = nil
            @helpers = {}
            @name = name.to_sym
            @on_set = nil
            @resetter = nil
            @setter = OptionDefinition::IDENTITY
            @type = nil
            @type_options = {}
            # If options were supplied, apply them.
            apply_options!(options)

            # Apply block if given.
            yield(self) if block_given?

            validate_options!
          end

          def env(value)
            @env = value
          end

          def deprecated_env(value)
            @deprecated_env = value
          end

          def env_parser(&block)
            @env_parser = block
          end

          def default(value = nil, &block)
            @default = block || value
          end

          def default_proc(&block)
            @default_proc = block
          end

          def helper(name, *_args, &block)
            @helpers[name] = block
          end

          def lazy(_value = true)
            Datadog::Core.log_deprecation do
              'Defining an option as lazy is deprecated for removal. Options now always behave as lazy. '\
              "Please remove all references to the lazy setting.\n"\
              'Non-lazy options that were previously stored as blocks are no longer supported. '\
              'If you used this feature, please let us know by opening an issue on: '\
              'https://github.com/datadog/dd-trace-rb/issues/new so we can better understand and support your use case.'
            end
          end

          def on_set(&block)
            @on_set = block
          end

          def resetter(&block)
            @resetter = block
          end

          def setter(&block)
            @setter = block
          end

          def type(value, nilable: false)
            @type = value
            @type_options = { nilable: nilable }

            value
          end

          # For applying options for OptionDefinition
          def apply_options!(options = {})
            return if options.nil? || options.empty?

            default(options[:default]) if options.key?(:default)
            default_proc(&options[:default_proc]) if options.key?(:default_proc)
            env(options[:env]) if options.key?(:env)
            deprecated_env(options[:deprecated_env]) if options.key?(:deprecated_env)
            env_parser(&options[:env_parser]) if options.key?(:env_parser)
            lazy(options[:lazy]) if options.key?(:lazy)
            on_set(&options[:on_set]) if options.key?(:on_set)
            resetter(&options[:resetter]) if options.key?(:resetter)
            setter(&options[:setter]) if options.key?(:setter)
            type(options[:type], **(options[:type_options] || {})) if options.key?(:type)
          end

          def to_definition
            OptionDefinition.new(@name, meta)
          end

          def meta
            {
              default: @default,
              default_proc: @default_proc,
              env: @env,
              deprecated_env: @deprecated_env,
              env_parser: @env_parser,
              on_set: @on_set,
              resetter: @resetter,
              setter: @setter,
              type: @type,
              type_options: @type_options
            }
          end

          private

          def validate_options!
            if !@default.nil? && @default_proc
              raise InvalidOptionError,
                'Using `default` and `default_proc` is not allowed. Please use one or the other.' \
                                'If you want to store a block as the default value use `default_proc`'\
                                ' otherwise use `default`'
            end
          end
        end
      end
    end
  end
end
