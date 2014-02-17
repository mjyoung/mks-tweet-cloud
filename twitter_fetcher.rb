require 'bundler'
require 'sinatra'
require 'json'
require 'rubygems'
require 'twitter'
require 'data_mapper'
require 'slim'

$CLOUD_BLACKLIST = %w(- @ @makersquare a am an and are at be do for from have i if i'm in is it it's its just like me my of on our out that the to rt so than this was we when with you your)

configure :development do
  DataMapper.setup(:default, ENV['Database_URL'] || "sqlite3://#{Dir.pwd}/development.db")

  # Load Twitter consumer and access keys and set global variables
  load 'twitter_credentials.rb'
end

configure :production do
  DataMapper.setup(:default, ENV['HEROKU_POSTGRESQL_ROSE_URL'])
  # To create the tables within Heroku, you will want to run in terminal:
  # heroku run console
  # $2.0.0-p0 :001>require './main.rb'
  # $2.0.0-p0 :002>DataMapper.auto_migrate!
  # May or may not also need to run:
  # $2.0.0-p0 :003>LastUpdated.auto_migrate!
  # $2.0.0-p0 :004>Tweet.auto_migrate!

  # Use Heroku's keys that I set within terminal console:
  # heroku config:set TWITTER_CONSUMER_KEY="abc123"
  # check all config settings with:  heroku config
  # If Heroku app doesn't run correctly, check logs with:  heroku logs
  $twitter_consumer_key = ENV['TWITTER_CONSUMER_KEY']
  $twitter_consumer_secret = ENV['TWITTER_CONSUMER_SECRET']
  $twitter_access_token = ENV['TWITTER_ACCESS_TOKEN']
  $twitter_access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
end

class LastUpdated
  include DataMapper::Resource
  property :id,            Serial
  property :last_updated,  DateTime, :required => true
  property :last_tweet_id, Integer,  :required => true, :max => 999999999999999999
  # 281474976710656
end

class Tweet
  include DataMapper::Resource
  property :id,         Serial
  property :tweet_id,   Integer,  :required => true, :max => 999999999999999999
  property :tweet_date, DateTime, :required => true
  property :user_name,  String,   :required => true
  property :user_id,    Integer,  :required => true, :max => 999999999999999999
  property :full_text,  Text,     :required => true
end

# When you update db structure, should do ClassName.auto_migrate! in pry
DataMapper.finalize

class TwitterFetcher < Sinatra::Base

  # Global twitter keys set in separate file. load file in config.ru
  client = Twitter::REST::Client.new do |config|
    config.consumer_key        = $twitter_consumer_key
    config.consumer_secret     = $twitter_consumer_secret
    config.access_token        = $twitter_access_token
    config.access_token_secret = $twitter_access_token_secret
  end

  get '/' do

    # this gets a list of Twitter:Tweet objects for the spring-2014 list
    # http://rdoc.info/gems/twitter/Twitter/Tweet
    # Can use list_tweets.each { |tweet| tweet_array << tweet.text }
    # list_tweets.each { |tweet| tweet.attrs }   # gives full hash of attrs info
    # then can get info and push into database:
    # list_tweets.each do |tweet|
    #   name = tweet[:user][:name]
    #   user_name = tweet[:user][:user_name]
    #   full_text = tweet[:full_text]
    # end

    @text_array = []
    @username_array = []
    @date_array = []

    if LastUpdated.count > 0  # If DB is not empty
      # The time is stored into the DB as DateTime. Need to parse to Time
      # in order to run 15-minute check in Ruby
      @last_updated = Time.parse(LastUpdated.last[:last_updated].to_s).utc

      @time_check = @last_updated + (15 * 60)

      @last_tweet_id = LastUpdated.last[:last_tweet_id]

      if @time_check < Time.now.utc
        @list_tweets = client.list_timeline(105076815, options = {:since_id => @last_tweet_id, :count => 200}).reverse
        @list_tweets.each do |tweet|
        tweet_id   = tweet[:id]
        tweet_date = tweet[:created_at]
        user_name  = tweet[:user][:user_name]
        user_id    = tweet[:user][:id]
        full_text  = tweet[:full_text]
        Tweet.create(:tweet_id => tweet_id,
                      :tweet_date => tweet_date,
                      :user_name => user_name,
                      :user_id => user_id,
                      :full_text => full_text)
        end

        if @list_tweets.length > 0
          LastUpdated.create(:last_updated => Time.now.utc,
                             :last_tweet_id => @list_tweets.last[:id])
        end

      end

    else # If DB is empty
      @list_tweets = client.list_timeline(105076815, options = {:count => 200}).reverse
      @list_tweets.each do |tweet|
      tweet_id   = tweet[:id]
      tweet_date = tweet[:created_at]
      user_name  = tweet[:user][:user_name]
      user_id    = tweet[:user][:id]
      full_text  = tweet[:full_text]
      Tweet.create(:tweet_id => tweet_id,
                    :tweet_date => tweet_date,
                    :user_name => user_name,
                    :user_id => user_id,
                    :full_text => full_text)
      end
      LastUpdated.create(:last_updated => Time.now.utc,
                         :last_tweet_id => @list_tweets.last[:id])
    end

    Tweet.all(:fields => [:full_text, :user_name, :tweet_date]).each do |tweet|
      @text_array << tweet[:full_text]
      @username_array << tweet[:user_name]
      @date_array << tweet[:tweet_date]
    end

    # The below 3 lines creates a hash of words and counts
    @word_array = @text_array.join(' ').split
    @word_count_hash = Hash.new(0)
    @word_array.each do |word|
      @word_count_hash[word] += 1 unless $CLOUD_BLACKLIST.include?(word.downcase)
    end

    @username_hash = Hash.new(0)
    @username_array.each do |username|
      @username_hash[username] += 1
    end

    @username_top3 = []
    @username_top3 = @username_hash.sort_by { |key, value| value }.reverse
    @username_top3 = @username_top3[0..2]

    slim :index

  end

  get '/last24' do

    @text_array = []

    Tweet.all(:tweet_date.gte => Time.now.utc-60*60*24).each do |tweet|
      @text_array << tweet[:full_text]
    end

    # The below 3 lines creates a hash of words and counts
    @word_array = @text_array.join(' ').split
    @word_count_hash = Hash.new(0)
    @word_array.each do |word|
      @word_count_hash[word] += 1 unless $CLOUD_BLACKLIST.include?(word.downcase)
    end

    slim :today

  end

  get '/response.json' do

    # This gets a list of followers.
    # Requires the ".attrs" method to convert Twitter::Cursor object to hash
    # http://rdoc.info/gems/twitter/Twitter/Cursor
    # my_hash = client.followers("immichaelyoung").attrs


    # this gets a list of Twitter:Tweet objects for the spring-2014 list
    # http://rdoc.info/gems/twitter/Twitter/Tweet
    # Can use list_tweets.each { |tweet| tweet_array << tweet.text }
    # list_tweets = client.list_timeline(105076815, options = {:count => 200})
    # tweet_array = []
    # list_tweets.each { |tweet| tweet_array << tweet.text }
    # tweet_array

  end

end



# id: 105076815 slug: 'spring-2014'

