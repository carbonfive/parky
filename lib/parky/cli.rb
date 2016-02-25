module Parky

  class CLI
    def initialize(opts)
      @options = { :verbose => false }.merge opts
      check_options

      slackbot = Slackbot.new(@config, @agent)
      daemon = Daemon.new(@agent, slackbot)
      @service = Service.new(@agent, daemon)
    end

    def run(params)
      @service.run
    end

    def start(params)
      @service.start
    end

    def stop(params)
      @service.stop
    end

    def restart(params)
      @service.restart
    end

    def status(params)
      @service.status
    end

  end
end
