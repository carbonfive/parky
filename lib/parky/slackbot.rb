require 'tzinfo'

module Parky
  class Slackbot
    def initialize(bot)
      Slacky::User.decorator = User

      @bot = bot
      @bot.on_help(&(method :help))
      @bot.on 'help',    &(method :help)
      @bot.on 'hello',   &(method :hello)
      @bot.on 'whatsup', &(method :whatsup)
      @bot.on 'reset',   &(method :reset)
      @bot.on String,    &(method :answer)

      @bot.client.on :presence_change do |data|
        next unless data['presence'] == 'active'
        user = Slacky::User.find data.user
        next unless user
        ask user
      end

      @tz_la = TZInfo::Timezone.get 'America/Los_Angeles'
      #@names = [ 'mike', 'rudy', 'rob', 'sueanna', 'crsven', 'justin', 'amanda', 'nate', 'yasmine', 'alexa' ]
      @names = [ 'mike' ]

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
    end

    def ask_all
      @names.each do |name|
        user = Slacky::User.find name
        ask user if user && user.presence == 'active'
      end
    end

    def ask(user)
      now = Time.now
      if user.should_ask_at?(now)
        im = @bot.client.web_client.im_open user: user.slack_id
        car = @car_emojis.sample
        message = "Hi #{user.username}!  Did you #{car} to work today?"
        @bot.client.web_client.chat_postMessage channel: im.channel.id, text: message
        user.slack_im_id = im.channel.id
        user.last_ask = now.to_i
        user.last_answer = nil
        user.save
      end
    end

    def help(user, data, args, &respond)
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
      true
    end

    def hello(user, data, args, &respond)
      if @names.include? user.username
        tz_now = user.tz.utc_to_local Time.now
        respond.call "Hello #{user.username}!  You are all set to use Parky."
        respond.call "Here is what I currently know about you:"
        respond.call <<EOM
```
today        : #{tz_now.strftime '%F'}
name         : #{user.first_name} #{user.last_name}
email        : #{user.email}
timezone     : #{user.timezone}
parking spot : #{user.parking_spot_status}
```
EOM
      else
        respond.call "Hello non-parking-spot-haver #{user.username}!"
        respond.call "You don't park in any of my spots, so clearly you're dead to me"
      end
      true
    end

    def whatsup(user, data, args, &respond)
      la_now = @tz_la.utc_to_local Time.now
      response = '```'
      response += "Parking spot statuses for #{la_now.strftime('%A %b %-d, %Y')}\n\n"
      statuses = {}
      n = @names.max_by { |name| name.length }.length
      @names.each do |name|
        user = Slacky::User.find name
        statuses[name] = user.parking_spot_status
      end
      statuses = statuses.sort_by { |tuple| "#{tuple[1]}-#{tuple[0]}" }
      statuses.each do |tuple|
        response += sprintf("%-#{n}s : %s", tuple[0], tuple[1]) + "\n"
      end
      response += '```'
      respond.call response
    end

    def reset(user, data, args, &respond)
      user.reset
      user.save
      hello user, data, args, &respond
      true
    end

    def answer(user, data, args, &respond)
      return false unless data.channel == user.slack_im_id
      return false unless data.text
      return false if data.text =~ /^parky/i

      if [ 'yes', 'y' ].include? data.text.downcase
        respond.call( rand(20) == 0 ? @yes.sample : "Ok thanks!" )
        user.last_answer = 'yes'
        user.save
      elsif [ 'no', 'n' ].include? data.text.downcase
        respond.call( rand(20) == 0 ? @no.sample : "Got it.  I'll mark it as available" )
        user.last_answer = 'no'
        user.save
      else
        respond.call "Hmmm.  I don't know what that means.  Try answering with 'yes' or 'no'."
      end

      true
    end
  end
end
