# hubot-twitter-subscriptions

Hubot plugin that subscribes a room to a/some Twitter stream/s.

Hubot's brain needs a redis server to memorize the subscriptions, please make sure you have it running. 

See [`src/twitter-stream.coffee`](src/twitter-stream.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-twitter-subscriptions --save`

Then add **hubot-twitter-subscriptions** to your `external-scripts.json`:

```json
[
  "hubot-twitter-subscriptions"
]
```

## Sample Interaction

```
user1>> hubot tws add foxnews
hubot>> @user1: Great! Anytime @foxnews tweets, I'll post it here.
```
