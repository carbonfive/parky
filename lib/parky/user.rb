class Parky::User
  attr_accessor :user_id, :im_id, :last_ask, :last_answer

  def initialize(attrs={})
    @user_id     = attrs[:user_id]
    @im_id       = attrs[:im_id]
    @last_ask    = attrs[:last_ask]
    @last_answer = attrs[:last_answer]
  end
end
