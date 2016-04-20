# Description
#   Hubot plugin that subscribes a room to a Twitter stream
#
# Configuration:
#   HUBOT_TWITTER_CONSUMER_KEY
#   HUBOT_TWITTER_CONSUMER_SECRET
#   HUBOT_TWITTER_ACCESS_TOKEN
#   HUBOT_TWITTER_ACCESS_TOKEN_SECRET
#
# Commands:
#   hubot tws add <screen_name> - Subscribes the current room to tweets from @screen_name
#   hubot tws rm <screen_name> - Unsubscribes the current room to tweets from @screen_name
#   hubot tws list - Lists the screen names the current room is subscribed to
#
# Author:
#   Andy Lindeman
#   Laura Lindeman
#   Isaac Roca


Twit = require 'twit'

consumer_key = process.env.HUBOT_TWITTER_CONSUMER_KEY
consumer_secret = process.env.HUBOT_TWITTER_CONSUMER_SECRET
access_token = process.env.HUBOT_TWITTER_ACCESS_TOKEN
access_token_secret = process.env.HUBOT_TWITTER_ACCESS_TOKEN_SECRET

class TwitterStreamSubscriptionManager
  BRAIN_KEY = "twitter-stream-room-follow-subscriptions"

  constructor: (@client, @brain, @callback) ->
    @streams = {}
    @loadSubscriptionsFromBrain()
    @brain.on 'loaded', => @loadSubscriptionsFromBrain()

  ensureSubscribedTo: (room, screen_name, callback) ->
    roomSubscriptions = @subscriptionsForRoom(room)
    roomStreams = @streamsForRoom(room)
    if roomStreams[screen_name]
      callback("This room is already subscribed to #{screen_name}")
    else
      roomSubscriptions[screen_name] = true
      @userIdForScreenName screen_name, (err, user_id) =>
        if err?
          callback(err) if callback
        else
          stream = roomStreams[screen_name] = @client.stream('statuses/filter', follow: user_id)
          stream.on 'tweet', (tweet) =>
            @callback(room, tweet) if @callback and tweet?.user?.id_str == user_id
          stream.on 'error', (error) ->
            console.log error
          callback(null) if callback

  ensureUnsubscribedFrom: (room, screen_name, callback) ->
    roomSubscriptions = @subscriptionsForRoom(room)
    roomStreams = @streamsForRoom(room)
    if stream = roomStreams[screen_name]
      stream.stop()
      delete roomStreams[screen_name]
      delete roomSubscriptions[screen_name]
    callback(null)

  roomSubscriptionsFromBrain: ->
    if subscriptions = @brain.get(BRAIN_KEY)
      subscriptions
    else
      subscriptions = {}
      @brain.set(BRAIN_KEY, subscriptions)
      subscriptions

  streamsForRoom: (room) ->
    @streams[room] ||= {}

  userIdForScreenName: (screen_name, callback) ->
    @client.get 'users/show', screen_name: screen_name, (err, data, response) ->
      if err?
        callback(err) if callback
      else
        callback(null, data.id_str) if callback

  subscriptionsForRoom: (room) ->
    roomSubscriptions = @roomSubscriptionsFromBrain()
    roomSubscriptions[room] ||= {}

  loadSubscriptionsFromBrain: ->
    roomSubscriptions = @roomSubscriptionsFromBrain()
    console.log roomSubscriptions
    for room, subscriptions of roomSubscriptions
      for subscription, _ of subscriptions
        console.log "Ensuring that #{room} is subscribed to user #{subscription}"
        @ensureSubscribedTo room, subscription

module.exports = (robot) ->
  constructStatusUrl = (tweet) ->
    "https://twitter.com/#{tweet.user.screen_name}/status/#{tweet.id_str}"
  sendTweetToRoom = (room, tweet) ->
    robot.send room: room, constructStatusUrl(tweet)

  if consumer_key and consumer_secret and access_token and access_token_secret
    client = new Twit
      consumer_key: consumer_key
      consumer_secret: consumer_secret
      access_token: access_token
      access_token_secret: access_token_secret
    subscriptionManager = new TwitterStreamSubscriptionManager(client, robot.brain, sendTweetToRoom)

    robot.respond /tws add @?(\S+)$/i, (msg) ->
      screen_name = msg.match[1]
      subscriptionManager.ensureSubscribedTo msg.message.user.room, screen_name, (err) ->
        if err?
          msg.reply "Something went wrong: #{err}"
        else
          msg.reply "Great! Anytime @#{screen_name} tweets, I'll post it here."

    robot.respond /tws rm @?(\S+)$/i, (msg) ->
      screen_name = msg.match[1]
      subscriptionManager.ensureUnsubscribedFrom msg.message.user.room, screen_name, (err) ->
        if err?
          msg.reply "Something went wrong: #{err}"
        else
          msg.reply "Roger that! I won't post tweets from @#{screen_name} anymore."

    robot.respond /tws list/i, (msg) ->
      subscriptions = Object.keys(subscriptionManager.subscriptionsForRoom(msg.message.user.room))
      msg.reply "This room is subscribed to: #{subscriptions.join(', ')}"


  else
    console.log "hubot-twitter-stream configuration variables missing"
