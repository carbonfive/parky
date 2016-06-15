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
      @bot.on_command 'claim',   &(method :claim)
      @bot.on_command 'unclaim', &(method :unclaim)
      @bot.on_im nil, &(method :answer)
      @bot.at '* * * * *', &(method :ask_all)

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
      return unless user.valid?

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
parky help               Show this message
parky hello              Say hello to me!
parky whatsup            Tell me what parking spots are available today
parky map                Show me who parks in each spot
parky claim <user>       Claim someone's unused spot for the day
parky claim <user> now!  No really, gimme that spot
parky unclaim            Release today's claimed spot

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
      response += "You can type 'parky map' to see who parks in each spot\n"
      response += "You can type 'parky claim <user>' to claim that user's spot (if it's available)"
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

    def claim(message)
      args = message.command_args.split ' '
      name = args[0] if args.length > 0
      c = claimed = Slacky::User.find name
      pc = previous_claimer = claimed && claimed.find_claimer
      now = args[1] if args.length > 1
      force = ( now == 'now!' )

      no_person       = "You need to specify who's spot you want to claim.  ex: `parky claim @jesus` (if she had a spot)"
      not_a_person    = "Sorry charlie.  #{args} is not a person, let alone a _parking_ person.  Try again.  :thumbsdown:"
      no_parking_spot = "No deal.  #{c && c.username} doesn't have a parking spot, so you can't claim it.  That's just _basic_ metaphysics. :face_with_rolling_eyes:"
      claimed_by_you  = "Ummm... you already have #{c && c.username}'s spot claimed.  So I guess you can still have it.  :happy_dooby:"
      too_slow        = "Too slow!  Looks like #{pc && pc.username} already claimed #{c && c.username}'s spot.  :disappointed:"
      not_available   = "Bzzzz!  #{c && c.username} hasn't released their spot today.  Swiper no swiping!  :no_entry_sign:"

      return ( message.reply no_person       ) if args.length == 0
      return ( message.reply not_a_person    ) unless claimed
      return ( message.reply no_parking_spot ) unless @config.usernames.include? claimed.username
      return ( message.reply claimed_by_you  ) if previous_claimer && previous_claimer.slack_id == message.user.slack_id
      return ( message.reply too_slow        ) if previous_claimer
      return ( message.reply not_available   ) unless claimed.parking_spot_status == 'available' || ( claimed.parking_spot_status == 'unknown' && force )

      message.user.claim claimed
      message.user.save
      message.reply "Boo ya!  You claimed #{claimed.username}'s spot for today.  :trophy:"
    end

    def unclaim(message)
      message.user.unclaim
      message.user.save
      message.reply "Ok, you no parky today.  kthxbai  :stuck_out_tongue_winking_eye:"
    end

    def answer(message)
      return if message.command?

      claimer = message.user.find_claimer

      if message.yes?
        message.reply( rand(10) == 0 ? @yes.sample : "Ok thanks!" )
        message.user.last_answer = 'yes'
        message.user.save
        if claimer
          message = "Whoops!  #{message.user.username} just stole their spot _back_ from you.  Sucker.  :middle_finger:"
          send_message claimer, message
        end
      elsif message.no?
        message.reply( rand(10) == 0 ? @no.sample : "Got it.  I'll mark it as available" )
        message.user.last_answer = 'no'
        message.user.save
        if claimer
          message = "Breaking news!  #{message.user.username} gave up their spot.  Looks like it's all yours.  :tada:"
          send_message claimer, message
        end
      else
        message.reply "Hmmm.  I don't know what that means.  Try answering with 'yes' or 'no'."
      end
    end

    def send_message(user, message)
      return unless user
      im = @bot.web_client.im_open user: user.slack_id
      @bot.web_client.chat_postMessage channel: im.channel.id, text: message, as_user: true
    end
  end
end
