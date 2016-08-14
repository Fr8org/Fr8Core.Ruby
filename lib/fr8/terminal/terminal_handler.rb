# frozen_string_literal: true
require 'trello'

module Fr8
  module Terminal
    # TODO: Document
    class TerminalHandler
      attr_accessor :terminal, :hub_factory, :authentication_handler,
                    :activity_store, :activities

      def initialize(
        terminal:, hub_factory: Hub.create_default_hub,
        activity_store: ActivityStore.new, activities: nil,
        authentication_handler: nil
      )
        method(__method__).parameters.each do |type, k|
          next unless type.to_s.starts_with?('key')
          v = eval(k.to_s)
          instance_variable_set("@#{k}", v) unless v.nil?
        end

        return if activities.nil?

        activities.each do |activity|
          self.activity_store.register_activity(
            activity_template: activity[0],
            activity_handler: activity[1]
          )
        end
      end

      def discover
        Fr8::Manifests::StandardFr8TerminalCM.new(
          definition: terminal,
          activities: activity_store.activity_templates_arr
        )
      end

      def configure(params)
        fr8_data_from_params(params, :configure)
      end

      def request_url(*)
        # Create a new OAuth consumer to make the request to the oauth API
        # with the correct request token path, access token path, and
        # authorize path.

        consumer = get_oauth_consumer

        callback_url = 'http://dev.fr8.co/AuthenticationCallback/' \
          'ProcessSuccessfulOAuthResponse?' \
          'terminalName=terminalTrello&terminalVersion=1'

        authorize_url = URI::HTTPS.build(
          host: 'trello.com',
          path: '/1/authorize',
          query: {
            callback_method: 'token',
            return_url: callback_url,
            scope: 'read,write',
            expiration: 'never',
            name: 'Fr8 Trello Terminal',
            key: ENV['TRELLO_API_KEY']
          }.to_query
        ).to_s

        request_token = consumer.get_request_token(
          {oauth_callback: callback_url},
          {scope: 'read,write', name: 'Ruby Trello Terminal'}
        )
          # name: 'Fr8 Trello Ruby Terminal',

        Fr8::Data::ExternalAuthUrlDTO.new(
          state_token: ENV['TRELLO_API_KEY'],
          url: request_token.authorize_url
        )
      end

      def token(params)
        external_token_dto =
          Fr8::Data::ExternalAuthenticationDTO.from_fr8_json(
            params.except(:terminal, :controller, :action)
          )

        oauth_token = external_token_dto.parameters['oauth_token']
        oauth_verifier = external_token_dto.parameters['oauth_verifier']
        oauth_hash = {
          oauth_token: oauth_token,
          oauth_token_secret: oauth_verifier
        }

        request_token = OAuth::RequestToken.from_hash(consumer, oauth_hash)
        access_token =
          request_token.get_access_token(oauth_verifier: oauth_verifier)

        ::Trello.configure do |config|
          config.consumer_key = ENV['TRELLO_API_KEY']
          config.consumer_secret = ENV['TRELLO_API_SECRET']
          config.oauth_token = access_token.token
          config.oauth_token_secret = access_token.secret
        end

        me = ::Trello::Member.find('me')

        result = Fr8::Data::AuthorizationTokenDTO.new(
          token: oauth_token,
          external_state_token: oauth_verifier,
          external_account_id: me.username
        )

        puts(result.as_json)

        result
      end

      def activate(params)
        fr8_data_from_params(params, :activate)
      end

      def deactivate(params)
        fr8_data_from_param(params, :deactivate)
      end

      private

      def get_oauth_consumer
        OAuth::Consumer.new(
          ENV['TRELLO_API_KEY'],
          ENV['TRELLO_API_SECRET'],
          site: 'https://trello.com',
          request_token_path: '/1/OAuthGetRequestToken',
          access_token_path: '/1/OAuthGetAccessToken',
          authorize_path: '/1/OAuthAuthorizeToken',
        )
      end

      def fr8_data_from_params(params, action)
        fr8_data =
          Fr8::Data::Fr8DataDTO.from_fr8_json(
            params.except(:terminal, :controller, :action)
          )
        activity_handler = activity_store.activity_handler_for(
          fr8_data.activity_dto.activity_template
        )
        activity_handler.send(action, fr8_json: params, fr8_data: fr8_data)
      end
    end
  end
end
