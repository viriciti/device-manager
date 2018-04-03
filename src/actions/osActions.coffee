_       = require "underscore"
request = require "request"
config  = require "config"
async   = require "async"
debug   = (require "debug") "app:actions:os"
io      = require "socket.io-client"

log = (require "../lib/Logger") "OS Updater"

module.exports = (state) ->

	reboot = (payload, cb) ->
		cb = _.once cb
		log.info "Received reboot command"
		state.setWork "Rebooting"

		{ host, port } = config.osUpdater.endpoint

		osUpdaterUrl = "http://#{host}:#{port}"

		_onLogs = (updateLog) ->
			log.info updateLog
			state.setWork updateLog

		socket = io osUpdaterUrl
		socket
			.on "error", (error) ->
				log.error error.message if error
				socket.close()
				cb new Error "Socket to ivh2-os-updater error triggered: #{error.message}"

			.on "logs", _onLogs

			.on "disconnect", ->
				log.info "Disconnected from os updater"
				socket.removeListener "logs", _onLogs

			.on "connect", ->
				log.info "Connected to os updater #{osUpdaterUrl}"

				socket.emit "reboot", (error) ->
					socket.close()

					if error
						return cb new Error "Received error after sending reboot command to ivh2-os-updater: #{error}"

					state.setWork "Reboot command received"
					cb()

	return { reboot }
