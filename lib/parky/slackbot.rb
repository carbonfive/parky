require 'slack-ruby-client'
require 'set'

module Parky
  class Slackbot
    def initialize(config)
      @config = config
      @restarts = []
      @channels = Set.new

      Slack.configure do |slack_cfg|
        slack_cfg.token = @config.slack_api_token
      end
    end

    def run
      unless @config.slack_api_token
        @config.log "No Slack API token found in parky.yml!"
        return
      end

      client = Slack::RealTime::Client.new
      @webclient = client.web_client
      auth = client.web_client.auth_test
      if auth['ok']
        @config.log "Slackbot is active!"
        @config.log "Accepting channels: #{@config.slack_accept_channels}" if @config.slack_accept_channels.length > 0
        @config.log "Ignoring channels: #{@config.slack_reject_channels}" if @config.slack_reject_channels.length > 0
      else
        puts "Slackbot cannot authorize with Slack.  Boo :-("
        @config.log "Slackbot is doomed :-("
        return
      end

      @config.users.populate client.web_client
      puts "Slackbot is active!"

      client.on :message do |data|
        next if data['user'] == @config.slackbot_id # this is Mr. Parky!
        next unless data['text']
        tokens = data['text'].split ' '
        channel = data['channel']
        next unless tokens.length > 0
        next unless tokens[0].downcase == 'parky'
        next if @config.slack_accept_channels.length > 0 and ! @config.slack_accept_channels.index(channel)
        next if @config.slack_reject_channels.index channel
        client.typing channel: channel
        @channels << channel
        respond = Proc.new { |msg| client.message channel: channel, reply_to: data.id, text: msg }
        method = tokens[1]
        args = tokens[2..-1]
        method = "#{method}_all" if args == [ 'all' ]
        ( help(data, [], &respond) and next ) unless method
        send method, data, args, &respond
      end

      client.on :presence_change do |data|
        next unless data['presence'] == 'active'
        id   = data.user
        info = @config.users.info id
        if info
          im = client.web_client.im_open user: info['id']
          message = "Hi #{info.name}!  Did you :car: to work today?"
          client.web_client.chat_postMessage channel: im['channel']['id'], text: message
        end
      end

      client.start!
    rescue => e
      @config.log "An error ocurring inside the Slackbot", e
      @restarts << Time.new
      @restarts.shift while (@restarts.length > 3)
      if @restarts.length == 3 and ( Time.new - @restarts.first < 30 )
        @config.log "Too many errors.  Not restarting anymore."
        client.on :hello do
          @channels.each do |channel|
            client.message channel: channel, text: "Oh no... I have died!  Please make me live again @mike"
          end
          client.stop!
        end
        client.start!
      else
        run
      end
    end

    def method_missing(name, *args)
      @config.log "No method found for: #{name}"
      @config.log args[0]
    end

    def user_profile(data)
      id = data['user']
      res = @webclient.users_info user: id
      return {} unless res['ok']
      profile = res['user']['profile']
      { id: id, first_name: profile['first_name'], last_name: profile['last_name'], email: profile['email'] }
    end

    def help(data, args, &respond)
      respond.call "Hello, I am Parky.  I can do the following things:"
      respond.call <<EOM
```
parky help              Show this message
parky hello             Say hello to me!
```
EOM
    end

    def blowup(data, args, &respond)
      respond.call "Tick... tick... tick... BOOM!   Goodbye."
      EM.next_tick do
        raise "kablammo!"
      end
    end

    def hello(data, args, &respond)
      profile = user_profile data
      respond.call "Hello #{profile[:first_name]}!  You are all set to use Parky."
      respond.call "I think this is you:"
      respond.call <<EOM
```
name:  #{profile[:first_name]} #{profile[:last_name]}
email: #{profile[:email]}
```
EOM
    end
  end
end
