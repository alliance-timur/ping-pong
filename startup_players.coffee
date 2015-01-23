cluster = require("cluster")
_ = require("lodash")
config = require("./config.js")
player = require("./player.coffee")
startWorkerPort = 3001
process.env.DEBUG = _.pluck(config.players, "name").join(",")
if cluster.isMaster
    # Fork workers.
    i = 0
    while i < config.players.length
        cluster.fork worker_id: i
        i++
    cluster.on "exit", (worker, code, signal) ->
        console.log "Worker " + worker.process.pid + " died"
else
    workerId = parseInt(process.env.worker_id, 10)
    player.run config.players[workerId]