require 'slack-ruby-client'
require 'set'
require 'tzinfo'

module Parky
  class Slackbot
    def initialize(config)
      @config = config
      @restarts = []
      @channels = Set.new
      @tz_la = TZInfo::Timezone.get 'America/Los_Angeles'
      @car_emojis = [ ':car:', ':blue_car:', ':oncoming_automobile:' ]
      @yes = [
        "Got it.  I'll make sure no one parks on top of your car.",
        "Great!  I'll tell Al Gore you don't care about global warming.",
        "Good thinking.  Walking and biking are for losers anyway.",
        "I thought so.  I heard people screaming in fear as you were driving up."
      ]
      @no = [
        "Really?  Well you still have to pay for the spot, sucker!",
        "Nice.  Finally getting off your ass and walking for a change, eh?",
        "Hmmm... Police scanner is saying a car just got stolen in your neighborhood.  Probably yours.",
        "Oh, did your drivers license finally get revoked from all those DUIs?"
      ]

      Slack.configure do |slack_cfg|
        slack_cfg.token = @config.slack_api_token
      end

      @client = Slack::RealTime::Client.new
      @users = Parky::Users.new @config, @client.web_client
      @users.populate
    end

    def run
      unless @config.slack_api_token
        @config.log "No Slack API token found in parky.yml!"
        return
      end

      auth = @client.web_client.auth_test
      if auth['ok']
        @config.log "Slackbot is active!"
        @config.log "Accepting channels: #{@config.slack_accept_channels}" if @config.slack_accept_channels.length > 0
        @config.log "Ignoring channels: #{@config.slack_reject_channels}" if @config.slack_reject_channels.length > 0
      else
        puts "Slackbot cannot authorize with Slack.  Boo :-("
        @config.log "Slackbot is doomed :-("
        return
      end

      puts "Slackbot is active!"

      # in case Parky was down when the user came online
      ask_all

      @client.on :message do |data|
        next if data.user == @config.slackbot_id # this is Mrs. Parky!
        next unless data.text
        tokens = data.text.split ' '
        channel = data.channel
        next unless tokens.length > 0
        next unless tokens[0].downcase == 'parky'
        next if @config.slack_accept_channels.length > 0 and ! @config.slack_accept_channels.index(channel)
        next if @config.slack_reject_channels.index channel
        @client.typing channel: channel
        @channels << channel
        respond = Proc.new { |msg| @client.message channel: channel, reply_to: data.id, text: msg }
        method = tokens[1]
        args = tokens[2..-1]
        ( help(data, [], &respond) and next ) unless method
        send method, data, args, &respond
      end

      @client.on :message do |data|
        next if data.user == @config.slackbot_id # this is Mrs. Parky!
        user = @users.find data.user
        next unless user

        next unless data.channel == user.dbuser.im_id
        next unless data.text
        next if data.text =~ /^parky/i

        respond = Proc.new { |msg| @client.message channel: data.channel, reply_to: data.id, text: msg }
        if [ 'yes', 'y' ].include? data.text.downcase
          respond.call( rand(20) == 0 ? @yes.sample : "Ok thanks!" )
          user.dbuser.last_answer = 'yes'
          user.dbuser.save
        elsif [ 'no', 'n' ].include? data.text.downcase
          respond.call( rand(20) == 0 ? @no.sample : "Got it.  I'll mark it as available" )
          user.dbuser.last_answer = 'no'
          user.dbuser.save
        else
          respond.call "Hmmm.  I don't know what that means.  Try answering with 'yes' or 'no'."
        end
      end

      @client.on :presence_change do |data|
        next unless data['presence'] == 'active'
        user = @users.find data.user
        next unless user
        ask user
      end

      @client.start!
    rescue => e
      @config.log "An error ocurring inside the Slackbot", e
      @restarts << Time.new
      @restarts.shift while (@restarts.length > 3)
      if @restarts.length == 3 and ( Time.new - @restarts.first < 30 )
        @config.log "Too many errors.  Not restarting anymore."
        @client.on :hello do
          @channels.each do |channel|
            @client.message channel: channel, text: "Oh no... I have died!  Please make me live again @mike"
          end
          @client.stop!
        end
        @client.start!
      else
        run
      end
    end

    def ask_all
      @users.refresh
      @users.all.each do |user|
        ask user if user['presence'] == 'active'
      end
    end

    def ask(user)
      now = Time.now
      if user.dbuser.should_ask_at?(now)
        im = @client.web_client.im_open user: user.id
        car = @car_emojis.sample
        message = "Hi #{user.name}!  Did you #{car} to work today?"
        @client.web_client.chat_postMessage channel: im.channel.id, text: message
        user.dbuser.im_id = im.channel.id
        user.dbuser.last_ask = now.to_i
        user.dbuser.last_answer = nil
        user.dbuser.save
      end
    end

    def method_missing(name, *args)
      @config.log "No method found for: #{name}"
      @config.log args[0].text
    end

    def help(data, args, &respond)
      respond.call "Hello, I am Parky.  I can do the following things:"
      respond.call <<EOM
```
parky help              Show this message
parky hello             Say hello to me!
parky whatsup           Tell me what parking spots are available today

If you have a parking spot, I will ask you each morning if you drove to work.
Please reply with 'yes' or 'no'.

Love, your friend - Mrs. Parky
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
      user = @users.find data.user
      if user
        la_now = @tz_la.utc_to_local Time.now
        respond.call "Hello #{user.name}!  You are all set to use Parky."
        respond.call "Here is what I currently know about you:"
        respond.call <<EOM
```
today        : #{la_now.strftime '%F'}
name         : #{user.profile.first_name} #{user.profile.last_name}
email        : #{user.profile.email}
parking spot : #{user.dbuser.parking_spot_status}
```
EOM
      else
        respond.call "Hello non-parking-spot-haver #{data.user}!"
        respond.call "You don't park in any of my spots, so clearly you're dead to me"
      end
    end

    def whatsup(data, args, &respond)
      la_now = @tz_la.utc_to_local Time.now
      response = '```'
      response += "Parking spot statuses for #{la_now.strftime('%A %b %-d, %Y')}\n\n"
      statuses = {}
      n = @users.names.max_by { |name| name.length }.length
      @users.all.each do |user|
        statuses[user.name] = user.dbuser.parking_spot_status
      end
      statuses = statuses.sort_by { |tuple| "#{tuple[1]}-#{tuple[0]}" }
      statuses.each do |tuple|
        response += sprintf("%-#{n}s : %s", tuple[0], tuple[1]) + "\n"
      end
      response += '```'
      respond.call response
    end

    def reset(data, args, &respond)
      user = @users.find data.user
      if user
        user.dbuser.reset
        user.dbuser.save
        hello data, args, &respond
      end
    end
  end
end
