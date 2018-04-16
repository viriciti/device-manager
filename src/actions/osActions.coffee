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

		{ host, port } = config.osUpdater

		osUpdaterUrl = "http://#{host}:#{port}/reboot"

		retryOpts =
			times:    10
			interval: (count) -> 50 * Math.pow 2, count

		async.retry retryOpts, (cb) ->
			request.post osUpdaterUrl, (error, result) ->
				if error
					state.publishLog "error", "OS updater unreachable"
					return cb error
				unless result.statusCode is 200
					state.publishLog "error", "OS updater statusCode #{result.statusCode}"
					return cb new Error "OS updater came back with #{result.statusCode}"

				state.setWork "Reboot command received"
				cb()
		, (error) ->
			state.publishLog "error", "Sending reboot failed: #{error.message}" if error
			cb error

	return { reboot }
