_       = require "underscore"
request = require "request"
config  = require "config"
async   = require "async"
debug   = (require "debug") "app:actions:os"
io      = require "socket.io-client"

log = (require "../lib/Logger") "OS Updater"

module.exports = (state) ->

	reboot = (payload, cb) ->
		log.info "Received reboot command"
		state.setWork "Rebooting"

		{ host, port } = config.osUpdater.endpoint

		osUpdaterUrl = "http://#{host}:#{port}"

		retryOpts =
			times:    10
			interval: (count) -> 50 * Math.pow 2, count

		async.retry retryOpts, (cb) ->
			request.post osUpdaterUrl, (error, result) ->
				if error
					state.addError "OS updater unreachable"
					return cb error
				state.setWork "Reboot command received"
				cb()
		, (error) ->
			state.addError "Sending reboot failed" if error
			cb error

	return { reboot }
