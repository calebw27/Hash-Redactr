configure do
  enable :sessions
end

helpers do

  def get_client
    @client = Twitter::REST::Client.new do |config|
      config.consumer_key = "jBlLVqrNSn7BY48FQFcVu9DjY"
      config.consumer_secret = "Y3hByR3vvFUSlXFouU5xC2eUeoGiqO2TTXJWeu1tUCODyFUK4f"
      config.access_token = session[:access_token]
      config.access_token_secret = session[:access_token_secret]
    end
    @client
  end

  def get_lists
    @hashtag_list = []
    @mention_list = []
    @user_list = []
    @home_timeline.each do |tweet|
      @user_list.concat([tweet.user.screen_name])
      tweet.hashtags.each do |tag|
        @hashtag_list.concat(["#".concat(tag.text)])
      end
      tweet.user_mentions.each do |mention|
        @mention_list.concat(["@".concat(mention.screen_name)])
      end
    end
  end

  def get_hashtag_frequency
    @hashtag_frequency = Hash.new(0)
    @hashtag_list.each { |tag| @hashtag_frequency[tag] += 1 }
    @hashtag_frequency = @hashtag_frequency.sort_by { |key, value| value }.reverse
  end

  def get_mention_frequency
    @mention_frequency = Hash.new(0)
    @mention_list.each { |mention| @mention_frequency[mention] += 1 }
    @mention_frequency = @mention_frequency.sort_by { |key, value| value }.reverse
  end

  def get_user_frequency
    @user_frequency = Hash.new(0)
    @user_list.each { |user| @user_frequency[user] += 1 }
    @user_frequency = @user_frequency.sort_by { |key, value| value }.reverse
  end

  def reset_filters
    session[:filters] = {hashtags: [], mentions: [], usernames: [], content: []}
  end

  def redacted?(tweet)
    !((tweet.hashtags.map { |hashtag| "#".concat(hashtag.text) } & session[:filters][:hashtags]).empty? &&
    (tweet.user_mentions.map { |mention| "@".concat(mention.screen_name) } & session[:filters][:mentions]).empty? && 
    ([tweet.user.screen_name] & session[:filters][:usernames]).empty? &&
    (tweet.text.downcase.split.map { |word| word.gsub(/\W$/, "") } & session[:filters][:content].map { |word| word.downcase }).empty?)
  end

end

get '/' do
  erb :index
end

get '/login' do
  redirect to("/auth/twitter?force_login=true")
end

get '/auth/twitter/callback' do
  if env['omniauth.auth']
    session[:logged_in] = true
    session[:access_token] = request.env['omniauth.auth']['credentials']['token']
    session[:access_token_secret] = request.env['omniauth.auth']['credentials']['secret']
    session[:username] = request.env['omniauth.auth']['info']['nickname']
    session[:profile_image] = request.env['omniauth.auth']['info']['image']
    session[:username] = request.env['omniauth.auth']['info']['nickname']
    session[:profile_image] = request.env['omniauth.auth']['info']['image']
    reset_filters
    user = User.find_by(access_token: session[:access_token])
    unless user.nil?
      session[:filters][:hashtags] = user[:hashtags].split
      session[:filters][:mentions] = user[:mentions].split
      session[:filters][:usernames] = user[:usernames].split
      session[:filters][:content] = user[:content].split
    end    
    redirect to ("/user")
  else
    halt(401,'Not Authorized')
  end
end

get '/auth/failure' do
  params[:message]
end

get '/user' do
  if session[:logged_in]
    @client = get_client
    @home_timeline = @client.home_timeline({count: 200})
    get_lists
    get_hashtag_frequency
    get_mention_frequency
    get_user_frequency
    erb :'user/index'
  else
    redirect to ("/login")
  end
end

post '/user' do
  case
  when params[:reset_filters]
    reset_filters
  when params[:hashtag_filter]
    session[:filters][:hashtags].include?(params[:hashtag_filter]) ? session[:filters][:hashtags].delete(params[:hashtag_filter]) : session[:filters][:hashtags].concat([params[:hashtag_filter]])
  when params[:mention_filter]
    session[:filters][:mentions].include?(params[:mention_filter]) ? session[:filters][:mentions].delete(params[:mention_filter]) : session[:filters][:mentions].concat([params[:mention_filter]])
  when params[:user_filter] 
    session[:filters][:usernames].include?(params[:user_filter]) ? session[:filters][:usernames].delete(params[:user_filter]) : session[:filters][:usernames].concat([params[:user_filter]])
  when params[:content_filter]
    session[:filters][:content].concat(params[:content_filter].split)
    session[:filters][:content] = session[:filters][:content].uniq
  when params[:remove_content_filter]
    session[:filters][:content].delete(params[:remove_content_filter])
  end
  user = User.find_by(access_token: session[:access_token])
  if user.nil?
    user = User.create(access_token: session[:access_token], hashtags: session[:filters][:hashtags], mentions: session[:filters][:mentions], usernames: session[:filters][:usernames], content: session[:filters][:content])
  else
    hashtag_filters = ""
    mention_filters = ""
    user_filters = ""
    content_filters = ""
    session[:filters][:hashtags].each { |hashtag| hashtag_filters << "#{hashtag} "}
    session[:filters][:mentions].each { |mention| mention_filters << "#{mention} "}
    session[:filters][:usernames].each { |user| user_filters << "#{user} "}
    session[:filters][:content].each { |word| content_filters << "#{word} "}
    user.update(hashtags: hashtag_filters, mentions: mention_filters, usernames: user_filters, content: content_filters)
  end
  redirect to ("/user")
end

post '/newtweet' do
  if session[:logged_in]
    @client = get_client
    @client.update(params[:compose_tweet])
    redirect to ('/user')
  end
end

get '/logout' do
  session.clear
  redirect to ("/")
end
