class Parky::Users
  def initialize
    @names = [ 'mike' ]
    @users = { }
  end

  def populate(client)
    print "Gather information about all the parking spot holders "
    @names.each do |name|
      info = client.users_info user: "@#{name}"
      unless info['ok']
        puts "Uh oh: #{info}"
        return
      end
      @users[info['user']['id']] = info['user']
      print '.'
    end
    puts ' done'
  end

  def info(id)
    @users[id]
  end

  def name(id)
    return nil unless info(id)
    info(id)['name']
  end
end
