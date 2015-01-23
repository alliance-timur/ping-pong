assert = require("assert")
restify = require("restify")
debug = require("debug")
_ = require("lodash")
config = require("./config.js")


class Player

    constructor: (options) ->
        _.extend @, options
        @log = debug @name
        @server = restify.createServer {@name}
        @_bindRoutes()
        @server.listen @port, =>
            @log "Listening server"
        @client = restify.createJsonClient(url: config.refereeURL)

    _wrapKey: (object) ->
        _.extend object,
            accessKey: @accessKey

    _bindRoutes: ->
        @server.use restify.bodyParser(mapParams: true)

        @server.post "/notification", (req, res) =>
            @log "Got notification", req.params.message
            res.send 200

        @server.post "/random", (req, res) =>
            attackerValue = _.random(1, 10)
            @log "Requested ramdom attackerValue", attackerValue
            res.send 200, {attackerValue}

        @server.post "/array", (req, res) =>
            arr = _.sample _.range(1, 10), @defenceLength
            @log "Requested array", arr
            res.send 200, arr

        @server.post "/kick", (req, res) =>
            @log "I'm dying..."
            res.send 200
#            process.exit(0)


    connect: ->
        @client.post "/welcome", @_wrapKey(
            name: @name
            accessKey: @accessKey
        ), (err, req, res, obj) =>
#            assert.ifError err
            if res?.statusCode isnt 200
                @log "Referee declined application because", obj.message
            else
                @log "Rarticipating in a tournament", obj.tournamentId

module.exports = run: (options) ->
    player = new Player(options)
    player.connect()
    player