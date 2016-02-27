class Parky::Users
  attr_reader :names

  def initialize(config, client)
    @config = config
    @client = client
    @names = [ 'mike', 'rudy', 'rob' ]
    @users = { }
  end

  def populate
    print "Gather information about all the parking spot holders "
    @names.each do |name|
      @config.log "Looking up user: @#{name}"
      resp = @client.users_info user: "@#{name}"
      unless resp.ok
        puts "Uh oh: #{info}"
        return
      end
      user = resp.user
      Parky::User.new(user_id: user.id).save unless Parky::User.find user.id
      refresh_one user
      @users[user.id] = user
      print '.'
    end
    puts ' done'
  end

  def refresh_one(user)
    presence = @client.users_getPresence user: user.id
    user.presence = presence['presence']
    user.dbuser = Parky::User.find user.id
    if ! user.dbuser.has_been_asked_on? Time.now
      user.dbuser.reset
      user.dbuser.save
    end
  end

  def refresh
    @users.each { |id, user| refresh_one user }
  end

  def find(id)
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
