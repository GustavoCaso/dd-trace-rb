# typed: true

require 'uri'
require 'set'

module Datadog
  module Tracing
    module Contrib
      module Utils
        module Quantization
          # Quantization for HTTP resources
          module HTTP
            include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)

            PLACEHOLDER = '?'.freeze

            module_function

            def url(url, options = {})
              url!(url, options)
            rescue StandardError
              options[:placeholder] || PLACEHOLDER
            end

            def base_url(url, options = {})
              URI.parse(url).tap do |uri|
                uri.path = ''
                uri.query = nil
                uri.fragment = nil
              end.to_s
            end

            def url!(url, options = {})
              options ||= {}

              URI.parse(url).tap do |uri|
                # Format the query string
                if uri.query
                  query = query(uri.query, options[:query])
                  uri.query = (!query.nil? && query.empty? ? nil : query)
                end

                # Remove any URI fragments
                uri.fragment = nil unless options[:fragment] == :show

                if options[:base] == :exclude
                  uri.host = nil
                  uri.port = nil
                  uri.scheme = nil
                end
              end.to_s
            end

            def query(query, options = {})
              query!(query, options)
            rescue StandardError
              options[:placeholder] || PLACEHOLDER
            end

            def query!(query, options = {})
              options ||= {}
              options[:obfuscate] = {} if options[:obfuscate] == :internal
              options[:show] = options[:show] || (options[:obfuscate] ? :all : [])
              options[:exclude] = options[:exclude] || []

              # Short circuit if query string is meant to exclude everything
              # or if the query string is meant to include everything
              return '' if options[:exclude] == :all

              query = collect_query(query, uniq: true) do |key, value|
                if options[:exclude].include?(key)
                  [nil, nil]
                else
                  value = (options[:show] == :all || options[:show].include?(key)) ? value : nil
                  [key, value]
                end
              end unless options[:show] == :all && !(options[:obfuscate] && options[:exclude])

              options[:obfuscate] ? obfuscate_query(query, options[:obfuscate]) : query
            end

            # Iterate over each key value pair, yielding to the block given.
            # Accepts :uniq option, which keeps uniq copies of keys without values.
            # e.g. Reduces "foo&bar=bar&bar=bar&foo" to "foo&bar=bar&bar=bar"
            def collect_query(query, options = {})
              return query unless block_given?

              uniq = options[:uniq].nil? ? false : options[:uniq]
              keys = Set.new

              delims = query.scan(/(^|&|;)/).flatten
              query.split(/[&;]/).collect.with_index do |pairs, i|
                key, value = pairs.split('=', 2)
                key, value = yield(key, value, delims[i])
                if uniq && keys.include?(key)
                  ''
                elsif key && value
                  "#{delims[i]}#{key}=#{value}"
                elsif key
                  "#{delims[i]}#{key}".tap { keys << key }
                # rubocop:disable Lint/DuplicateBranch
                else
                  ''
                end
                # rubocop:enable Lint/DuplicateBranch
              end.join.sub(/^[&;]/, '')
            end

            private_class_method :collect_query

            # Scans over the query string and obfuscates sensitive data by
            # replacing matches with an opaque value
            def obfuscate_query(query, options = {})
              options[:regex] = nil if options[:regex] == :internal
              re = options[:regex] || OBFUSCATOR_REGEX
              with = options[:with] || OBFUSCATOR_WITH

              query.gsub(re, with)
            end

            private_class_method :obfuscate_query

            OBFUSCATOR_WITH = '<redacted>'.freeze
            OBFUSCATOR_REGEX = %r{
              (?: # JSON-ish leading quote
                 (?:"|%22)?
              )
              (?: # common keys
                 p(?:ass)?w(?:or)?d # pw, password variants
                |pass(?:_?phrase)?  # pass, passphrase variants
                |secret
                |(?: # key, key_id variants
                     api_?
                    |private_?
                    |public_?
                    |access_?
                    |secret_?
                 )key(?:_?id)?
                |token
                |consumer_?(?:id|key|secret)
                |sign(?:ed|ature)?
                |auth(?:entication|orization)?
              )
              (?:
                 # '=' query string separator, plus value til next '&' separator
                 (?:\s|%20)*(?:=|%3D)[^&]+
                 # JSON-ish '": "somevalue"', key being handled with case above, without the opening '"'
                |(?:"|%22)                                     # closing '"' at end of key
                 (?:\s|%20)*(?::|%3A)(?:\s|%20)*               # ':' key-value spearator, with surrounding spaces
                 (?:"|%22)                                     # opening '"' at start of value
                 (?:%2[^2]|%[^2]|[^"%])+                       # value
                 (?:"|%22)                                     # closing '"' at end of value
              )
             |(?: # other common secret values
                 bearer(?:\s|%20)+[a-z0-9._\-]+
                |token(?::|%3A)[a-z0-9]{13}
                |gh[opsu]_[0-9a-zA-Z]{36}
                |ey[I-L](?:[\w=-]|%3D)+\.ey[I-L](?:[\w=-]|%3D)+(?:\.(?:[\w.+/=-]|%3D|%2F|%2B)+)?
                |-{5}BEGIN(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY-{5}[^\-]+-{5}END(?:[a-z\s]|%20)+PRIVATE(?:\s|%20)KEY
                |ssh-rsa(?:\s|%20)*(?:[a-z0-9/.+]|%2F|%5C|%2B){100,}
              )
            }ix.freeze
          end
        end
      end
    end
  end
end
