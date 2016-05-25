require 'tzinfo'

module Parky
  class Slackbot
    def initialize(bot)
      Slacky::User.decorator = User

      @config = bot.config
      @config.extend Config

      @bot = bot
      @bot.on_command 'help',    &(method :help)
      @bot.on_command 'hello',   &(method :hello)
      @bot.on_command 'whatsup', &(method :whatsup)
      @bot.on_command 'map',     &(method :map)
      @bot.on_command 'reset',   &(method :reset)
      @bot.on_im nil, &(method :answer)
      @bot.at '*/5 * * * *', &(method :ask_all)

      @bot.on :presence_change do |data|
        next unless ( user = Slacky::User.find data.user )
        ask user
      end

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

      @config.log "Parky recognizes parkers: #{users.map(&:username)}"
      puts        "Parky recognizes parkers: #{users.map(&:username)}"

      ask_all
    end

    def users
      Slacky::User.find @config.usernames
    end

    def ask_all
      users.each do |user|
        ask user if user.presence == 'active'
      end
    end

    def ask(user)
      return unless @config.usernames.include? user.username
      return unless user.presence == 'active'

      now = Time.now
      should_ask = ! user.has_been_asked_on?(now)
      should_ask &&= user.is_work_hours?(now) if @config.work_hours_only?
      if should_ask
        im = @bot.web_client.im_open user: user.slack_id
        car = @car_emojis.sample
        message = "Hi #{user.username}!  Did you #{car} to work today?"
        @bot.web_client.chat_postMessage channel: im.channel.id, text: message, as_user: true
        user.slack_im_id = im.channel.id
        user.last_ask = now.to_i
        user.last_answer = nil
        user.save
      end
    end

    def help(message)
      message.reply "Hello, I am Parky.  I can do the following things:"
      message.reply <<EOM
```
parky help              Show this message
parky hello             Say hello to me!
parky whatsup           Tell me what parking spots are available today
parky map               Show me who parks in each spot

If you have a parking spot, I will ask you each morning if you drove to work.
Please reply with 'yes' or 'no'.

Love, your friend - Mrs. Parky
```
EOM
      true
    end

    def hello(message)
      if @config.usernames.include? message.user.username
        tz_now = message.user.tz.utc_to_local Time.now
        message.reply "Hello #{message.user.username}!  You are all set to use Parky."
        message.reply "Here is what I currently know about you:"
        message.reply <<EOM
```
today        : #{tz_now.strftime '%F'}
name         : #{message.user.first_name} #{message.user.last_name}
email        : #{message.user.email}
timezone     : #{message.user.timezone}
parking spot : #{message.user.parking_spot_status}
```
EOM
      else
        message.reply "Hello non-parking-spot-haver #{message.user.username}!"
        message.reply "You don't park in any of my spots, so clearly you're dead to me"
      end
    end

    def whatsup(message)
      la_now = @tz_la.utc_to_local Time.now
      response = '```'
      response += "Parking spot statuses for #{la_now.strftime('%A %b %-d, %Y')}\n\n"
      statuses = {}
      n = users.map(&:username).map(&:length).max
      users.each do |user|
        statuses[user.username] = user.parking_spot_status
      end
      statuses = statuses.sort_by { |tuple| "#{tuple[1]}-#{tuple[0]}" }
      statuses.each do |tuple|
        response += sprintf("%-#{n}s : %s", tuple[0], tuple[1]) + "\n"
      end
      response += "\n"
      response += "You can type 'parky map' to see who parks in each spot"
      response += '```'
      message.reply response
    end

    def map(message)
      @bot.web_client.chat_postMessage channel: message.channel.slack_id, text: "Ok gimme a second to pull this out of my ass..... ets directory", as_user: true
      root = "#{File.dirname(__FILE__)}/../.."
      file = "#{root}/assets/images/parking-map.jpg"
      upload = UploadIO.new file, 'image/jpg'
      @bot.web_client.files_upload file: upload, filetype: 'jpg', filename: 'parking-map.jpg', title: 'Carbon Five LA parking map', channels: message.channel.slack_id
    end

    def reset(message)
      message.user.reset
      message.user.save
      hello message
    end

    def answer(message)
      return if message.command?

      if message.yes?
        message.reply( rand(10) == 0 ? @yes.sample : "Ok thanks!" )
        message.user.last_answer = 'yes'
        message.user.save
      elsif message.no?
        message.reply( rand(10) == 0 ? @no.sample : "Got it.  I'll mark it as available" )
        message.user.last_answer = 'no'
        message.user.save
      else
        message.reply "Hmmm.  I don't know what that means.  Try answering with 'yes' or 'no'."
      end
    end
  end
end
