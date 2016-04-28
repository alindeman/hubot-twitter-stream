# Description
#   Hubot plugin that subscribes a room to a Twitter stream
#
# Configuration:
#   HUBOT_TWITTER_CONSUMER_KEY
#   HUBOT_TWITTER_CONSUMER_SECRET
#   HUBOT_TWITTER_ACCESS_TOKEN
#   HUBOT_TWITTER_ACCESS_TOKEN_SECRET
#   HUBOT_TWS_DEBUG_ROOM (optional)
#
# Commands:
#   hubot tws add <screen_name> - Subscribes the current room to tweets from @screen_name
#   hubot tws rm <screen_name> - Unsubscribes the current room to tweets from @screen_name
#   hubot tws list - Lists the screen names the current room is subscribed to
#
# Author:
#   Isaac Roca

Twit = require 'twit'

CONSUMER_KEY = process.env.HUBOT_TWITTER_CONSUMER_KEY
CONSUMER_SECRET = process.env.HUBOT_TWITTER_CONSUMER_SECRET
ACCESS_TOKEN = process.env.HUBOT_TWITTER_ACCESS_TOKEN
ACCESS_TOKEN_SECRET = process.env.HUBOT_TWITTER_ACCESS_TOKEN_SECRET
DEBUG_ROOM = process.env.HUBOT_TWS_DEBUG_ROOM

BRAIN_KEY = "twitter-room-subscriptions"
LOG_PREFIX = "twitter-subscriptions: "

module.exports = (robot) ->

  logInfo = (msg) -> robot.logger.info LOG_PREFIX + msg
  logError = (msg) -> robot.logger.error LOG_PREFIX + msg
  logDevRoom = (msg) -> robot.send room: DEBUG_ROOM, msg if DEBUG_ROOM?

  unless CONSUMER_KEY? and CONSUMER_SECRET? and ACCESS_TOKEN? and ACCESS_TOKEN_SECRET?
    logError "Missing Twitter configuration variables. Not loading."
    return

  tw_client = new Twit
    consumer_key: CONSUMER_KEY
    consumer_secret: CONSUMER_SECRET
    access_token: ACCESS_TOKEN
    access_token_secret: ACCESS_TOKEN_SECRET
  tw_stream = null
  tws_brain = null

  userFromScreenName = (screen_name_input, callback) ->
    tw_client.get 'users/show', screen_name: screen_name_input, (err, data, response) ->
      callback err, { user_id: data.id_str, screen_name: data.screen_name }
  
  resetStream = (callback) ->
    tw_stream.stop() if tw_stream?
    user_ids = Object.keys(tws_brain)
    if user_ids.length > 0
      tw_stream = tw_client.stream 'statuses/filter', follow: user_ids.join(',')
      tw_stream.on 'tweet', (tweet) ->
        return unless tweet?.user?.id_str?
        if tws_brain[tweet.user.id_str]?
          logInfo '@' + tws_brain[tweet.user.id_str].name + ' tweet emitted: ' + tweet.text
          robot.emit "new_tweet", tws_brain[tweet.user.id_str].rooms, tweet
      tw_stream.on 'error', (err) ->
        logDevroom '*Error*: ' + err.message
        callback(err)
      tw_stream.on 'limit', (o) -> logDevRoom '*LIMIT*: ' + JSON.stringify(o)
      tw_stream.on 'disconnect', (o) -> logDevRoom '*DISCONNECT*: ' + JSON.stringify(o)
      tw_stream.on 'connect', (o) -> logDevRoom '*CONNECT*: ' + JSON.stringify(o)
      tw_stream.on 'connected', (o) -> logDevRoom '*CONNECTED*: ' + JSON.stringify(o)
      tw_stream.on 'reconnect', (o) -> logDevRoom '*RECONNECT*: ' + JSON.stringify(o)
      tw_stream.on 'warning', (o) -> logDevRoom '*WARNING*: ' + JSON.stringify(o)
      tw_stream.on 'unknown_user_event', (o) -> logDevRoom '*UNKNOWN_USER_EVENT*: ' + JSON.stringify(o)

  robot.error (err, res) ->
    logError err
    res.reply "Error: " + err if res?

  robot.brain.on 'loaded', ->
    tws_brain = robot.brain.get BRAIN_KEY
    tws_brain = robot.brain.set BRAIN_KEY, {} unless tws_brain?
    if !Object.keys(tws_brain).length
      logInfo "There are no subscriptions to load from radis brain."
      return
    logInfo "Loading subscriptions from radis brain: " + JSON.stringify(tws_brain, null, '\t')
    resetStream (err) ->
      logError "Something went wrong connecting to Twitter: #{err}. Exiting." if err?

  robot.on "new_tweet", (rooms, tweet) ->
    for room in rooms
      robot.send room: room, "#{tweet.text} (@#{tweet.user.screen_name})\n
        https://twitter.com/#{tweet.user.screen_name}/status/#{tweet.id_str}"

  robot.respond /tws add @?(\S+)$/i, (msg) ->
    userFromScreenName msg.match[1], (err, user) ->
      if err?
        msg.reply "Something went wrong connecting to Twitter: #{err}"
        return
      tws_brain[user.user_id] = { name:'', rooms: [] } unless tws_brain[user.user_id]?
      if msg.message.user.room in tws_brain[user.user_id].rooms
        msg.reply "Oops! This room is already subscribed to @#{user.screen_name}."
        return
      tws_brain[user.user_id].name = user.screen_name
      tws_brain[user.user_id].rooms.push msg.message.user.room
      msg.reply "Great! Anytime @#{user.screen_name} tweets, I'll post it here."
      logInfo "Adding subscription. Room: #{msg.message.user.room} Username: @#{user.screen_name}"
      resetStream (err) ->
        msg.reply "Something went wrong: #{err}" if err?

  robot.respond /tws rm @?(\S+)$/i, (msg) ->
    userFromScreenName msg.match[1], (err, user) ->
      if err?
        msg.reply "Something went wrong connecting to Twitter: #{err}"
        return
      unless tws_brain[user.user_id]? and msg.message.user.room in tws_brain[user.user_id].rooms
        msg.reply "I'm sorry but this room was not subscribed to @#{user.screen_name}."
        return
      tws_brain[user.user_id].rooms = tws_brain[user.user_id].rooms.filter (e) -> e != msg.message.user.room
      delete tws_brain[user.user_id] if tws_brain[user.user_id].rooms.length == 0
      msg.reply "Roger that! I won't post tweets from @#{user.screen_name} anymore."
      logInfo "Removing subscription. Room: #{msg.message.user.room} Username: @#{user.screen_name}"
      resetStream (err) ->
        msg.reply "Something went wrong: #{err}" if err?

  robot.respond /tws list/i, (msg) ->
    subscriptions = []
    for uid, obj of tws_brain
      if obj.rooms?
        for room in obj.rooms
          subscriptions.push obj.name if room == msg.message.user.room
    if subscriptions.length > 0
      msg.reply "This room is subscribed to: @#{subscriptions.join(' | @')}"
    else
      msg.reply "This room has no subscriptions."

  robot.respond /tws brain/i, (msg) ->
    msg.reply JSON.stringify(tws_brain, null, '\t')

