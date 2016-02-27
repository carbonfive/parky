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

      @config.users.populate @client.web_client, @config
      puts "Slackbot is active!"

      # in case Parky was down when the user came online
      ask_all

      @client.on :message do |data|
        next if data.user == @config.slackbot_id # this is Mr. Parky!
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
        next if data.user == @config.slackbot_id # this is Mr. Parky!
        info = @config.users.info data.user
        next unless info

        user = @config.get_dbuser info.id
        unless user
          @config.log "Strange.  Can't find user: #{info.id}"
          next
        end

        next unless data.channel == user.im_id
        next if data.text =~ /^parky/

        respond = Proc.new { |msg| @client.message channel: data.channel, reply_to: data.id, text: msg }
        if data.text == 'yes'
          respond.call( rand(30) == 0 ? @yes.sample : "Ok thanks!" )
          user.last_answer = data.text
          @config.save_dbuser user
        elsif data.text == 'no'
          respond.call( rand(30) == 0 ? @no.sample : "Got it.  I'll mark it as available" )
          user.last_answer = data.text
          @config.save_dbuser user
        else
          respond.call "Hmmm.  I don't know what that means.  Try answering with 'yes' or 'no'."
        end
      end

      @client.on :presence_change do |data|
        next unless data['presence'] == 'active'
        info = @config.users.info data.user
        next unless info
        ask info
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

    def is_work_hours?(time)
      la_time = @tz_la.utc_to_local time.getgm
      return false if la_time.wday == 0 || la_time.wday == 6  # weekends
      la_time.hour >= 8 && la_time.hour <= 17
    end

    def ask_all
      @config.users.refresh
      @config.users.all.each do |info|
        ask info if info['presence'] == 'active'
      end
    end

    def ask(info)
      user = @config.get_dbuser info.id
      user = Parky::User.new user_id: info.id unless user

      now = Time.now
      if is_work_hours?(now) && ! user.has_been_asked_on?(now)
        im = @client.web_client.im_open user: info.id
        car = @car_emojis.sample
        message = "Hi #{info.name}!  Did you #{car} to work today?"
        @client.web_client.chat_postMessage channel: im.channel.id, text: message
        user.im_id = im.channel.id
        user.last_ask = now.to_i
        user.last_answer = nil
        @config.save_dbuser user
      end
    end

    def method_missing(name, *args)
      @config.log "No method found for: #{name}"
      @config.log args[0]
    end

    def help(data, args, &respond)
      respond.call "Hello, I am Parky.  I can do the following things:"
      respond.call <<EOM
```
parky help              Show this message
parky hello             Say hello to me!
parky whatsup           Tell me what parking spots are available today
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
      info = @config.users.info data.user
      if info
        user = @config.get_dbuser info.id
        la_now = @tz_la.utc_to_local Time.now
        respond.call "Hello #{info.name}!  You are all set to use Parky."
        respond.call "Here is what I currently know about you:"
        respond.call <<EOM
```
today        : #{la_now.strftime '%F'}
name         : #{info.profile.first_name} #{info.profile.last_name}
email        : #{info.profile.email}
parking spot : #{user.parking_spot_status}
```
EOM
      end
    end

    def whatsup(data, args, &respond)
      la_now = @tz_la.utc_to_local Time.now
      response = '```'
      response += "Parking spot statuses for #{la_now.strftime('%A %b %-d, %Y')}\n\n"
      statuses = {}
      n = @config.users.names.max_by { |name| name.length }.length
      @config.users.all.each do |user|
        dbuser = @config.get_dbuser user.id
        statuses[user.name] = dbuser.parking_spot_status
      end
      statuses = statuses.sort_by { |tuple| "#{tuple[1]}-#{tuple[0]}" }
      statuses.each do |tuple|
        response += sprintf("%-#{n}s : %s", tuple[0], tuple[1]) + "\n"
      end
      response += '```'
      respond.call response
    end

    def reset(data, args, &respond)
      user = @config.get_dbuser data.user
      if user
        user.last_ask = nil
        user.last_answer = nil
        @config.save_dbuser user
        hello data, args, &respond
      end
    end
  end
end
