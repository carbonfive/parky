class Parky::Users
  attr_reader :names

  def initialize(config)
    @config = config
    @names = [ 'mike', 'rudy', 'rob' ]
    @users = { }
  end

  def populate(client)
    @client = client
    print "Gather information about all the parking spot holders "
    @names.each do |name|
      @config.log "Looking up user: @#{name}"
      info = @client.users_info user: "@#{name}"
      unless info.ok
        puts "Uh oh: #{info}"
        return
      end
      user = @config.get_dbuser info.user.id
      @config.save_dbuser Parky::User.new user_id: info.user.id unless user
      @users[info.user.id] = info.user
      print '.'
    end
    puts ' done'
  end

  def refresh
    @users.each do |id, info|
      presence = @client.users_getPresence user: id
      info.presence = presence['presence']
    end
  end

  def info(id)
    @users[id]
  end

  def all
    @users.values
  end

  def name(id)
    return nil unless info(id)
    info(id)['name']
  end
end
