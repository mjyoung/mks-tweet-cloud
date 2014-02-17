require 'bundler'
require 'sinatra'
require 'json'
require 'rubygems'
require 'twitter'
require 'data_mapper'
require 'slim'

# require_relative '00-twitter-credentials'


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

    @list_tweets = client.list_timeline(105076815, options = {:count => 11})
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
                       :last_tweet_id => @list_tweets.first[:id])

    Tweet.all(:fields => [:full_text]).each do |tweet|
      @text_array << tweet[:full_text]
    end

    # The below 3 lines creates a hash of words and counts
    @word_array = @text_array.join(' ').split
    @word_count_hash = Hash.new(0)
    @word_array.each { |word| @word_count_hash[word] += 1 }

    slim :index

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

