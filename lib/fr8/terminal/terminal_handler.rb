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

      def request_url(request)
        # Create a new OAuth consumer to make the request to the oauth API
        # with the correct request token path, access token path, and
        # authorize path.

        consumer = new_oauth_consumer

        hub_url = request.headers['FR8HUBCALLBACKURL']
        request_token =
          consumer.get_request_token(oauth_callback: callback_url(hub_url))
        params =
          { scope: 'read,write,account', name: 'Fr8 Trello Ruby Terminal' }

        Fr8::Data::ExternalAuthUrlDTO.new(
          external_state_token: request_token.token,
          url: "#{request_token.authorize_url}&#{params.to_query}"
        )
      end

      def token(params, request)
        external_token_dto =
          Fr8::Data::ExternalAuthenticationDTO.from_fr8_json(
            params.except(:terminal, :controller, :action)
          )

        oauth_token = external_token_dto.parameters['oauth_token']
        oauth_verifier = external_token_dto.parameters['oauth_verifier']

        consumer = new_oauth_consumer
        hub_url = request.headers['FR8HUBCALLBACKURL']
        request_token =
          consumer.get_request_token(oauth_callback: callback_url(hub_url))
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
          token: access_token.to_json,
          external_state_token: oauth_token,
          external_account_id: me.username
        )

        result
      end

      def activate(params)
        fr8_data_from_params(params, :activate)
      end

      def deactivate(params)
        fr8_data_from_param(params, :deactivate)
      end

      private

      def callback_url(hub_url)
        "#{hub_url}/AuthenticationCallback/ProcessSuccessfulOAuthResponse?" \
          'terminalName=terminalTrello&terminalVersion=1'
      end

      def new_oauth_consumer
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
