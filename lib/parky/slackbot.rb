require 'tzinfo'

module Parky
  class Slackbot
    def initialize(bot)
      bot.on 'help',    &(method :help)
      bot.on 'hello',   &(method :hello)
      bot.on 'whatsup', &(method :whatsup)
      bot.on 'reset',   &(method :reset)

      @names = [ 'mike', 'rudy', 'rob', 'sueanna', 'crsven', 'justin', 'amanda', 'nate', 'yasmine', 'alexa' ]

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

      ask_all

      #@users = Parky::Users.new @config, @client.web_client
      #@users.populate
    end

    def run
      # in case Parky was down when the user came online
      ask_all

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
    end

    def ask_all
      @names.each do |name|
        user = Slacky::User.find name
        ask user if user && user.presence == 'active'
      end
    end

    def ask(user)
      now = Time.now
      parky_user = User.new user
      if parky_user.should_ask_at?(now)
        im = @client.web_client.im_open user: user.id
        car = @car_emojis.sample
        message = "Hi #{user.name}!  Did you #{car} to work today?"
        @client.web_client.chat_postMessage channel: im.channel.id, text: message
        user.slack_im_id = im.channel.id
        user.data['last_ask'] = now.to_i
        user.data['last_answer'] = nil
        user.save
      end
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

    def hello(data, args, &respond)
      user = User.find data.user
      if user
        parky_user = User.new user
        tz_now = user.tz.utc_to_local Time.now
        respond.call "Hello #{user.name}!  You are all set to use Parky."
        respond.call "Here is what I currently know about you:"
        respond.call <<EOM
```
today        : #{tz_now.strftime '%F'}
name         : #{user.profile.first_name} #{user.profile.last_name}
email        : #{user.profile.email}
timezone     : #{user.timezone}
parking spot : #{parky_user.parking_spot_status}
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
      user = User.find data.user
      if user
        user.reset
        user.save
        hello data, args, &respond
      end
    end
  end
end
