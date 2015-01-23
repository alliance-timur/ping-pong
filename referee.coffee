assert = require("assert")
restify = require("restify")
debug = require("debug")
_ = require("lodash")
async = require("async")
util = require("util")
EventEmitter = require("events").EventEmitter
config = require("./config.js")



class Referee

    constructor: (options) ->
        @options = options
        @log = debug("Referee")
        @tournament = new Tournament(4)
        @server = restify.createServer(name: "Referee")
        @_bindRoutes()
        @server.listen @options.port, =>
            @log "Listening server"

    _bindRoutes: ->
        @server.use restify.bodyParser(mapParams: true)
        @server.use (req, res, next) ->
            accessKey = req.params.accessKey
            return next(new Error("accessKey is not specified"))  if _.isUndefined(accessKey)
            player = _.find(config.players,
                accessKey: accessKey
            )
            return next(new Error("No users with given accessKey found"))  unless player
            req.player = new PlayerClient(player)
            next()

        @server.post "/welcome", (req, res, next) =>
            @log "User connection attempt", req.player.name
            status = @tournament.addPlayer req.player
            if @tournament.isStarted
                return res.json 403, message: 'Current tournament has already started. Registration is closed.'
            unless status
                res.json 403, message: "Player is in a tournament already"
            else
                @log "User #{req.player.name} successfully added to the tournament"
                res.json 200, tournamentId: @tournament.id
                @tournament.emit 'tick'


class PlayerClient

    constructor: (options) ->
        @log = debug("PlayerClient:#{@name}")
        _.extend @, options
        @client = restify.createJsonClient(url: "http://localhost:#{@port}/")

    notification: (info, callback) ->
        @client.post "/notification", {message: info}, (err, req, res, obj) ->
            callback? err

    requestRandom: (callback)->
        @client.post "/random", (err, req, res, obj) ->
            callback? err, obj


    requestArray: (callback)->
        @client.post "/array", (err, req, res, obj) ->
            callback? err, obj

    kick: ->
        @client.post "/kick", (err)->
            assert.ifError(err)



class Game extends EventEmitter

    constructor: ({@tournament, @players}) ->
        @id = Math.random().toString().slice(2)
        @log = debug("Game:#{@id}")
        @on "tick", @_nextTick
        @isFinished = no
        @isStarted = no
        _.each @players, (player)->
            _.extend player, {score: 0, isWinner: no}
        [@attacker, @defender] = @players
        @_turnIndex = null
        @log 'Created'

    _swapRoles: ->
        [@attacker, @defender] = [@defender, @attacker]

    _nextTurn: ->
#        @log '_nextTurn', @_turnIndex
        unless @_turnIndex?
            @_turnIndex = 0
        else
            @_turnIndex = (@_turnIndex + 1) % 3
        switch ['attacker', 'defender', 'results'][@_turnIndex]
            when 'attacker'
                @attacker.requestRandom (err, {@attackerValue})=>
                    assert.ifError(err)
                    @log "attacker value #{@attackerValue}"
                    @emit 'tick'
            when 'defender'
                @defender.requestArray (err, @defenceArray)=>
                    assert.ifError(err)
                    @log "defence array #{@defenceArray}"
                    @emit 'tick'
            when 'results'
                isDefenceSucceed = _.contains @defenceArray, @attackerValue
                if isDefenceSucceed
                    @defender.score++
                    @log "Defender [#{@defender.name}] gets 1 score point. The score is #{@defender.score}"
                    @_swapRoles()
                else
                    @attacker.score++
                    @log "Attacker [#{@attacker.name}] gets 1 score point. The score is #{@attacker.score}"
                @defenceArray = null
                @attackerValue = null
                @emit 'tick'

    _nextTick: ->
#        @log 'nextTick'

        unless @isStarted
            @isStarted = yes
            return @emit 'tick'

        if winner = _.find([@attacker, @defender], {score: 5})
            winner.isWinner = yes
            @log "The winner is #{winner.name}"
            @isFinished = yes
            return @tournament.emit 'tick'

        @_nextTurn()




class Tournament extends EventEmitter

    constructor: ->
        @id = Math.random().toString().slice(2)
        @log = debug("Tournament:#{@id}")
        @on "tick", @_nextTick
        @players = []
        @capacity = config.players.length
        if @capacity % 2 isnt 0
            throw 'Capacity of tournament may not be odd, exiting...'
            process.exit(0)
        @report = {games: []}
        @_reset()

    addPlayer: (player) ->
        isKeyFound = _.find(@players, accessKey: player.accessKey)
        return false if isKeyFound
        @players.push player
        return true

    _addLoopReport: ->
        @report.games.push _.map @_games, (game)->
            return {
                gameId: game.id
                scores: _.map game.players, (player)->
                    return {name: player.name, score: player.score}
            }

    _reset: ->
        @isStarted = no
        @table = null
        @_gameIndex = null
        @_games = []
        @currentGame = null

    _start: ->
        @players = _.shuffle(@players)
        @gamesCount = Math.floor(@players.length / 2)
        @table = _.map _.range(@gamesCount), (index) =>
            return [
                @players[2 * index]
                @players[2 * index + 1]
            ]
        async.eachSeries @players, ((player, cb) =>
            playerIndex = _.findIndex(@players, player)
            gameTurnOrder = Math.floor(playerIndex / 2) + 1
            role = ['attacker (first)', 'defender (second)'][playerIndex % 2]
            player.notification(
                "Your tournament #{@id} is started. Your game turn order is #{gameTurnOrder}. Your first role is #{role}"
            , cb)
        ), (errors, results) =>
            @log "Everybody notified"
            @isStarted = true
            @emit 'tick'


    _nextTick: ->
#        @log 'nextTick'

        unless @isStarted
            if @players.length is @capacity
                @log "Starting..."
                return @_start()
            else
                return null

        if @currentGame? and not @currentGame.isStarted
            return @currentGame.emit 'tick'


        if not @currentGame? or @currentGame.isFinished
            unless @_gameIndex?
                @_gameIndex = 0
            else
                @_gameIndex++
            if @_gameIndex is @gamesCount
                @_addLoopReport()
                @log 'Next tournament loop...'
                @players = _.filter @players, (player)=>
                    unless player.isWinner
                        @log "Kicnking #{player.name}"
                        player.kick()
                    return player.isWinner
                remainingPlayers = _.pluck(@players, 'name').join(', ')
                @log "Remaining players #{remainingPlayers}"
                @capacity = @capacity / 2
                if @capacity is 1
                    winner = _.first(@players)
                    winner.notification('You are the winner!')
                    @log "Tournament is finished and the cup winner is #{winner.name}"
                    @log 'The report', JSON.stringify(@report, null, 2)
                    return
                @_reset()
                return @emit 'tick'

            @log "Next game"
            @currentGame = new Game(
                tournament: @
                players: @table[@_gameIndex]
            )
            @_games.push @currentGame
            return @emit 'tick'



module.exports = run: (options) ->
    new Referee(options)