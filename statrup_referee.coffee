config = require("./config.js")
referee = require("./referee.coffee")
process.env.DEBUG = "*"
referee.run port: config.refereePort